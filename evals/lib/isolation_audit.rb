# frozen_string_literal: true

# Isolation audit for eval runs: did the model gain access to information an
# isolated delegate should not have, or write where it may not?
#
# It is not a lexical path detector. Each tool call is reduced to filesystem
# events (read, write, exec, cwd change) by role: a grep pattern, a heredoc
# body written to a file, or a name passed to the model's own script is data,
# not an access. Each event's path is resolved (cwd tracking, variables,
# tilde, symlinks the run created, the macOS data-volume firmlink, case) and
# classified by location; its status comes from the call's observed result
# (tool error, rejection, an error naming that path) and, where the trace
# cannot show it, from what the runtime enforced for that location.
#
# Dimensions, reported separately:
#   external_read      a read of a host or protected location succeeded -> invalid
#   external_write     a write outside workspace/allowed scratch succeeded -> invalid
#   reference_exposure hidden reference content appeared in model-visible
#                      tool output -> invalid
#   cwd_escape         commands ran from outside the workspace (recorded;
#                      permitted when the task declares cwd independence)
#   path_string_mentions  lexical markers (~/, ../, $HOME, ...) in commands;
#                      diagnostic only, never invalidating
# A read or write that cannot be proven either way is "unknown": recorded
# for a human, never invalidating by itself. Incomplete trace coverage makes
# the read dimension at least "unknown".

require "json"
require "shellwords"
require "tmpdir"

module Evals
  module IsolationAudit
    VERSION = "isolation-audit-v2"
    MIN_CANARY = 32

    # Location classes. host: user homes, volumes and network mounts;
    # protected: the evals tree, this repo and the eval source repos; other:
    # anything else outside the system directories (including /.vol and
    # /.file, which address files by id). Reads of "other" are unknown.
    HOST_ROOTS = %w[/Users /Volumes /home /Network].freeze
    RUNTIME_ROOTS = %w[/usr /bin /sbin /System /Library /opt /etc /Applications /nix /var /cores /private /dev].freeze
    DEVICE = %r{\A/dev/(null|zero|u?random|stdin|stdout|stderr|tty|fd(/|\z))}i
    SCRATCH = [%r{\A/tmp(/|\z)}i, %r{\A/var/folders/[^/]+/[^/]+/T(/|\z)}i].freeze
    TMPDIR_SENTINEL = "/tmp/.eval-runtime-tmpdir"
    LEGACY_MARKERS = ["evals/hidden", "~/", "$HOME", "${HOME}", "../"].freeze
    UNAUTHORIZED = %w[host protected].freeze
    GLOB = /[*?\[{]/
    READ_ERROR = /No such file or directory|Permission denied|Operation not permitted|not found|cannot (?:open|access)/

    # ------------------------------------------------------------ shell lexer

    Word = Struct.new(:segs, :raw) do
      # segs: [:lit, text] | [:tilde, user] | [:var, name] | [:cmd, source] |
      # [:nested, [sources]] (unknown value whose inner commands still run)
      def literal = segs.all? { |t, _| t == :lit } ? segs.map(&:last).join : nil
    end

    class ParseError < StandardError; end

    class Lexer
      def initialize(src)
        @s = src.to_s
        @i = 0
        @toks = []
        @heredocs = []
      end

      def run
        loop do
          skip_blanks
          break if @i >= @s.size
          c = @s[@i]
          if c == "\n"
            @i += 1
            @toks << [:op, ";"]
            read_heredoc_bodies
          elsif c == "#"
            @i += 1 while @i < @s.size && @s[@i] != "\n"
          elsif @s[@i, 2] == "&&" || @s[@i, 2] == "||" || @s[@i, 2] == ";;"
            @toks << [:op, @s[@i, 2]]
            @i += 2
          elsif ["<(", ">("].include?(@s[@i, 2])
            # process substitution: the inner command runs; its value is a pipe
            j = balanced(@i + 1)
            @toks << [:word, Word.new([[:cmd, @s[(@i + 2)...(j - 1)]]], @s[@i...j])]
            @i = j
          elsif (m = @s[@i..].match(/\A(\d*)(<<-|<<<|<<|&>>|&>|>>|>\||>&|<&|<>|>|<)/))
            @i += m[0].size
            skip_blanks
            target = read_word
            raise ParseError, "redirection without target" unless target
            r = { op: m[2], fd: m[1], target: target }
            if ["<<", "<<-"].include?(m[2])
              r[:quoted] = target.raw.match?(/['"\\]/) # quoted delimiter: no expansion in the body
              @heredocs << [r, target.segs.map(&:last).join, m[2] == "<<-"]
            end
            @toks << [:redir, r]
          elsif ";|&()".include?(c)
            @toks << [:op, c]
            @i += 1
          else
            @toks << [:word, read_word]
          end
        end
        raise ParseError, "unterminated heredoc" unless @heredocs.empty?
        @toks
      end

      # $(...) and `...` sources inside text that the shell expands (an
      # unquoted heredoc body): those commands run.
      def self.substitutions(text)
        lx = new(text)
        lx.send(:scan_substitutions)
      end

      private

      def scan_substitutions
        out = []
        while @i < @s.size
          if @s[@i] == "\\"
            @i += 2
          elsif @s[@i, 2] == "$(" && @s[@i, 3] != "$(("
            j = balanced(@i + 1)
            out << @s[(@i + 2)...(j - 1)]
            @i = j
          elsif @s[@i] == "`"
            j = @s.index("`", @i + 1) or raise ParseError, "unterminated backtick"
            out << @s[(@i + 1)...j]
            @i = j + 1
          else
            @i += 1
          end
        end
        out
      end

      def skip_blanks
        loop do
          if @s[@i] == " " || @s[@i] == "\t" then @i += 1
          elsif @s[@i, 2] == "\\\n" then @i += 2
          else break
          end
        end
      end

      def read_heredoc_bodies
        until @heredocs.empty?
          r, delim, strip = @heredocs.shift
          body = +""
          loop do
            raise ParseError, "unterminated heredoc" if @i >= @s.size
            nl = @s.index("\n", @i) || @s.size
            line = @s[@i...nl]
            @i = [nl + 1, @s.size].min
            cmp = strip ? line.sub(/\A\t+/, "") : line
            break if cmp == delim
            body << line << "\n"
          end
          r[:body] = body
        end
      end

      def read_word
        start = @i
        segs = []
        lit = +""
        flush = -> { (segs << [:lit, lit.dup]; lit.clear) unless lit.empty? }
        if @s[@i] == "~" && (m = @s[@i..].match(%r{\A~([A-Za-z0-9_.-]*)(?=/|\s|\z|[;&|()<>])}))
          segs << [:tilde, m[1]]
          @i += m[0].size
        end
        while @i < @s.size
          c = @s[@i]
          break if " \t\n;&|()<>".include?(c)
          case c
          when "'"
            j = @s.index("'", @i + 1) or raise ParseError, "unterminated quote"
            lit << @s[(@i + 1)...j]
            @i = j + 1
          when '"'
            @i += 1
            while @i < @s.size && @s[@i] != '"'
              if @s[@i] == "\\" && "$`\"\\\n".include?(@s[@i + 1].to_s)
                lit << @s[@i + 1] unless @s[@i + 1] == "\n"
                @i += 2
              elsif @s[@i] == "$" || @s[@i] == "`"
                flush.call
                segs << read_dollar
              else
                lit << @s[@i]
                @i += 1
              end
            end
            raise ParseError, "unterminated quote" if @i >= @s.size
            @i += 1
          when "\\"
            lit << @s[@i + 1].to_s
            @i += 2
          when "$", "`"
            if @s[@i, 2] == "$'"
              j = @i + 2
              j += (@s[j] == "\\" ? 2 : 1) while j < @s.size && @s[j] != "'"
              lit << @s[(@i + 2)...j]
              @i = j + 1
            else
              flush.call
              segs << read_dollar
            end
          else
            lit << c
            @i += 1
          end
        end
        flush.call
        return nil if @i == start
        Word.new(segs, @s[start...@i])
      end

      # $(...), $((...)), ${...}, $NAME, $1, $@, `...`
      def read_dollar
        if @s[@i] == "`"
          j = @i + 1
          j += (@s[j] == "\\" ? 2 : 1) while j < @s.size && @s[j] != "`"
          raise ParseError, "unterminated backtick" if j >= @s.size
          src = @s[(@i + 1)...j]
          @i = j + 1
          return [:cmd, src]
        end
        if @s[@i, 3] == "$(("
          j = balanced(@i + 1)
          inner = @s[(@i + 3)...(j - 2)]
          @i = j
          return [:nested, Lexer.substitutions(inner)]
        end
        if @s[@i, 2] == "$("
          j = balanced(@i + 1)
          src = @s[(@i + 2)...(j - 1)]
          @i = j
          return [:cmd, src]
        end
        if @s[@i, 2] == "${"
          j = brace_end(@i + 1)
          inner = @s[(@i + 2)...(j - 1)]
          @i = j
          name = inner[/\A[A-Za-z_][A-Za-z0-9_]*\z/]
          return [:var, name] if name
          # ${X:-$(cmd)} and other operators: unknown value, inner commands run
          return [:nested, Lexer.substitutions(inner)]
        end
        if (m = @s[@i..].match(/\A\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])/))
          @i += m[0].size
          return [:var, m[1] =~ /\A[A-Za-z_]/ ? m[1] : nil]
        end
        @i += 1
        [:lit, "$"]
      end

      # Index just past the "}" matching the "{" at pos, skipping quotes and
      # nested ${...} / $(...).
      def brace_end(pos)
        depth = 0
        j = pos
        while j < @s.size
          case @s[j]
          when "{" then depth += 1
          when "}"
            depth -= 1
            return j + 1 if depth.zero?
          when "(" then j = balanced(j) - 1
          when "'" then j = @s.index("'", j + 1) || @s.size
          when "\\" then j += 1
          end
          j += 1
        end
        raise ParseError, "unterminated ${"
      end

      # Index just past the ")" matching the "(" at pos, skipping quotes.
      def balanced(pos)
        depth = 0
        j = pos
        while j < @s.size
          case @s[j]
          when "(" then depth += 1
          when ")"
            depth -= 1
            return j + 1 if depth.zero?
          when "'" then j = @s.index("'", j + 1) || @s.size
          when '"'
            j += 1
            j += (@s[j] == "\\" ? 2 : 1) while j < @s.size && @s[j] != '"'
          when "\\" then j += 1
          end
          j += 1
        end
        raise ParseError, "unbalanced $("
      end
    end

    # ------------------------------------------------------------ parser

    # Nodes: {t: :simple, words:, redirs:, pipe:} | {t: :sub, body:} |
    # {t: :group, body:, subject:} | {t: :func, name:, body:} | {t: :for, var:, words:}
    class Parser
      PREFIX_KEYWORDS = %w[if then else elif while until do ! time].freeze
      END_KEYWORDS = %w[fi done esac].freeze

      def initialize(toks)
        @t = toks
        @i = 0
      end

      def run
        nodes = sequence
        raise ParseError, "unexpected #{@t[@i].inspect}" if @i < @t.size
        nodes
      end

      private

      def peek = @t[@i]
      def op?(v) = peek && peek[0] == :op && peek[1] == v
      def word_is?(v) = peek && peek[0] == :word && peek[1].literal == v

      def sequence(stop_op: nil, stop_words: [])
        nodes = []
        loop do
          @i += 1 while peek && peek[0] == :op && [";", "&", "&&", "||"].include?(peek[1])
          break if peek.nil?
          break if stop_op && op?(stop_op)
          break if stop_words.any? { |w| word_is?(w) }
          break if op?(";;")
          nodes.concat(pipeline(stop_words))
        end
        nodes
      end

      def pipeline(stop_words)
        parts = [command(stop_words)]
        while op?("|") || (peek && peek[0] == :op && peek[1] == "|&")
          @i += 1
          parts << command(stop_words)
        end
        parts.compact!
        parts.each { |n| n[:pipe] = true } if parts.size > 1
        parts
      end

      def command(stop_words)
        if op?("(")
          @i += 1
          body = sequence(stop_op: ")")
          raise ParseError, "unclosed (" unless op?(")")
          @i += 1
          return { t: :sub, body: body, redirs: trailing_redirs }
        end
        if word_is?("{")
          @i += 1
          body = sequence(stop_words: ["}"])
          raise ParseError, "unclosed {" unless word_is?("}")
          @i += 1
          return { t: :group, body: body, redirs: trailing_redirs }
        end
        if word_is?("[[")
          # [[ ... ]] is one test expression: && || ( ) and < > inside it are
          # operators of the test, not of the shell
          words = [peek[1]]
          @i += 1
          until peek.nil? || word_is?("]]")
            tok = peek
            words << tok[1] if tok[0] == :word
            words << tok[1][:target] if tok[0] == :redir
            @i += 1
          end
          raise ParseError, "unclosed [[" unless word_is?("]]")
          words << peek[1]
          @i += 1
          return { t: :simple, words: words, redirs: trailing_redirs }
        end
        if word_is?("for")
          @i += 1
          var = peek && peek[0] == :word ? peek[1].literal : nil
          @i += 1
          words = []
          if word_is?("in")
            @i += 1
            while peek && peek[0] == :word
              words << peek[1]
              @i += 1
            end
          end
          return { t: :for, var: var, words: words }
        end
        if word_is?("case")
          @i += 1
          subject = peek && peek[0] == :word ? peek[1] : nil
          @i += 1
          raise ParseError, "case without in" unless word_is?("in")
          @i += 1
          body = []
          loop do
            @i += 1 while peek && peek[0] == :op && peek[1] == ";"
            break if peek.nil? || word_is?("esac")
            @i += 1 if op?("(")
            @i += 1 while peek && !op?(")") # pattern words and | separators
            raise ParseError, "bad case pattern" unless op?(")")
            @i += 1
            body.concat(sequence(stop_words: ["esac"]))
            @i += 1 if op?(";;")
          end
          raise ParseError, "unclosed case" unless word_is?("esac")
          @i += 1
          return { t: :group, body: body, subject: subject, redirs: trailing_redirs }
        end
        words = []
        redirs = []
        loop do
          tok = peek
          break if tok.nil?
          if tok[0] == :word
            lit = tok[1].literal
            break if words.empty? && stop_words.include?(lit)
            if words.empty? && (PREFIX_KEYWORDS.include?(lit) || END_KEYWORDS.include?(lit))
              @i += 1
              next
            end
            words << tok[1]
            @i += 1
            # name() { body }  -- function definition
            if words.size == 1 && op?("(") && @t[@i + 1] && @t[@i + 1][0] == :op && @t[@i + 1][1] == ")"
              @i += 2
              @i += 1 while peek && peek[0] == :op && peek[1] == ";"
              body = command(stop_words)
              return { t: :func, name: words.first.literal, body: [body].compact }
            end
          elsif tok[0] == :redir
            redirs << tok[1]
            @i += 1
          else
            break
          end
        end
        return nil if words.empty? && redirs.empty?
        { t: :simple, words: words, redirs: redirs }
      end

      def trailing_redirs
        out = []
        while peek && peek[0] == :redir
          out << peek[1]
          @i += 1
        end
        out
      end
    end

    # ------------------------------------------------------------ locations

    Ctx = Struct.new(:host, :workspace, :home, :protected, :enforce, :policy, keyword_init: true)

    # Canonical form: absolute, "." and ".." resolved, the macOS data-volume
    # firmlink and /private aliases removed.
    def self.norm(path)
      return nil if path.nil?
      p = File.expand_path(path, "/")
      # alias spellings of the same file (case-insensitive volume)
      loop do
        q = p.sub(%r{\A/\.nofollow(?=/|\z)}i, "").sub(%r{\A/\.resolve/\d+(?=/|\z)}i, "").sub(%r{\A/System/Volumes/Data(?=/|\z)}i, "")
        q = "/" if q.empty?
        break if q == p
        p = q
      end
      p.sub(%r{\A/private(?=/(?:tmp|var|etc)(?:/|\z))}i, "")
    end

    # Path containment on a case-insensitive volume.
    def self.within?(path, root)
      a = path.downcase
      b = root.downcase
      a == b || a.start_with?(b.end_with?("/") ? b : "#{b}/")
    end

    # Location class of an absolute path. A recursive read of an ancestor of
    # the home or a protected root reaches into it; a glob is judged by the
    # directory before its first wildcard, recursively.
    def self.location(path, ctx, recursive: false)
      return "unknown" if path.nil?
      n = norm(path)
      if n.match?(GLOB)
        dir = norm(n[0...n.index(GLOB)].sub(%r{[^/]*\z}, "")) || "/"
        # a wildcard in the last segment names entries of dir; deeper ones reach below
        recursive ||= n[dir.size..].to_s.sub(%r{\A/}, "").sub(%r{/\z}, "").include?("/")
        n = dir
      end
      return "workspace" if within?(n, ctx.workspace)
      return "protected" if ctx.protected.any? { |r| within?(n, r) || (recursive && within?(r, n)) }
      return "host" if ([ctx.home] + HOST_ROOTS).any? { |r| within?(n, r) || (recursive && within?(r, n)) }
      return "device" if n.match?(DEVICE)
      return "scratch" if SCRATCH.any? { |re| n.match?(re) }
      return "runtime" if n == "/" || RUNTIME_ROOTS.any? { |r| within?(n, r) && !within?(n, "/var/root") }
      "other"
    end

    # ------------------------------------------------------------ evaluator

    PATTERN_FIRST = %w[grep egrep fgrep rg ag ack jq yq fd].freeze
    READERS = %w[cat head tail less more nl wc od xxd hexdump strings file stat ls tree du sort uniq cut paste column fold
                 tac rev cksum md5 md5sum shasum sha1sum sha256sum base64 diff cmp comm bat realpath readlink source . codegraph].freeze
    RECURSIVE = %w[rg ag ack tree du codegraph fd].freeze
    WRITERS = %w[mkdir touch rm rmdir truncate unlink mkfifo tee].freeze
    MODE_WRITERS = %w[chmod chown chgrp].freeze
    COPIERS = %w[cp mv rsync install].freeze
    SHELLS = %w[bash sh zsh dash ksh].freeze
    INTERPRETERS = %w[python python2 python3 ruby node perl php osascript swift].freeze
    WRAPPERS = %w[command builtin exec nohup time nice stdbuf sudo].freeze
    NO_ACCESS = (%w[echo printf true false : exit return set unset shift trap wait sleep date pwd whoami uname id hostname which
                    type hash alias read getopts let basename dirname seq expr tr printenv mktemp popd pushd cd test] + ["[", "[["]).freeze
    OPT_ARGS = {
      "grep" => %w[-e -f -A -B -C -m --regexp --file --max-count --include --exclude --exclude-dir],
      "rg" => %w[-e -f -g -t -T -A -B -C -m -M -j --regexp --file --glob --iglob --type --type-not --max-count --max-columns --threads],
      "sed" => %w[-e -f --expression --file], "awk" => %w[-f -v -F], "head" => %w[-n -c], "tail" => %w[-n -c],
      "cut" => %w[-d -f -c -b], "sort" => %w[-k -t -o -T], "xargs" => %w[-I -n -P -L -d -E -s], "jq" => %w[--arg --argjson --slurpfile --rawfile],
      "find" => [], "diff" => %w[-U -x -X], "ls" => [], "tar" => %w[-C -f], "ln" => %w[-t],
      "timeout" => %w[-s -k], "nice" => %w[-n], "mktemp" => %w[-t -p], "python3" => %w[-c -m], "ruby" => %w[-e -r -I],
      "git" => %w[-C -c --git-dir --work-tree -m -b -B -o --origin --depth --reference --separate-git-dir --branch --format --pretty --author -n
                  -S -G -e -f --grep --committer --since --until --max-count -U --abbrev]
    }.freeze
    GIT_WRITE = %w[add commit init apply checkout reset restore stash rm mv clean switch merge rebase tag am cherry-pick revert clone fetch pull worktree].freeze
    SEMANTIC = (PATTERN_FIRST + READERS + WRITERS + MODE_WRITERS + COPIERS + SHELLS + INTERPRETERS + WRAPPERS + NO_ACCESS +
                %w[git find sed awk gawk mawk nawk dd tar ln env timeout xargs eval export local declare readonly]).freeze

    class Evaluator
      attr_reader :events, :unparsed

      def initialize(ctx)
        @ctx = ctx
        @events = []
        @unparsed = 0
        @funcs = {}
        @links = {} # symlinks this run created: link path -> target path
        @remotes = {} # git remotes this run configured: name -> url
      end

      # Analyses one shell command string run from cwd; returns the final cwd.
      def shell(src, cwd:, call:, vars: {})
        nodes = Parser.new(Lexer.new(src).run).run
        state = { cwd: cwd, vars: vars.dup }
        walk(nodes, state, call)
        state[:cwd]
      rescue ParseError => e
        @unparsed += 1
        opaque(src, call, via: "unparsed shell (#{e.message})")
        cwd
      end

      def event(kind, path, call, via:, recursive: false)
        path = through_links(path)
        loc = IsolationAudit.location(path, @ctx, recursive: recursive)
        @events << { "call" => call[:index], "kind" => kind, "path" => path, "location" => loc, "via" => via,
                     "recursive" => recursive || nil, "status" => nil, "_call" => call }.compact
      end

      private

      def through_links(path)
        return path if path.nil? || @links.empty?
        n = IsolationAudit.norm(path)
        @links.each do |link, target|
          return target + n[link.size..] if IsolationAudit.within?(n, link)
        end
        path
      end

      def walk(nodes, state, call)
        nodes.each do |n|
          case n[:t]
          when :simple then simple(n, n[:pipe] ? copy(state) : state, call)
          when :sub
            Array(n[:redirs]).each { |r| redirect(r, state, call) }
            walk(n[:body], copy(state), call)
          when :group
            values(n[:subject], state, call) if n[:subject]
            Array(n[:redirs]).each { |r| redirect(r, state, call) }
            walk(n[:body], state, call)
          when :func
            @funcs[n[:name]] = true
            walk(n[:body], copy(state), call)
          when :for
            vals = n[:words].flat_map { |w| values(w, state, call) }
            state[:vars][n[:var]] = vals.empty? ? [nil] : vals if n[:var]
          end
        end
      end

      def copy(state) = { cwd: state[:cwd], prev: state[:prev], vars: state[:vars].dup, path_entries: state[:path_entries] }

      # All candidate values of a word (list-valued loop variables expand).
      def values(word, state, call)
        acc = [+""]
        word.segs.each do |type, v|
          parts = case type
                  when :lit then [v]
                  when :tilde then [v.empty? ? @ctx.home : nil]
                  when :var then var_values(v, state)
                  when :cmd then [cmd_value(v, state, call)]
                  when :nested
                    v.each { |src| shell(src, cwd: state[:cwd], call: call, vars: state[:vars]) }
                    [nil]
                  end
          acc = acc.product(parts).map { |a, b| a.nil? || b.nil? ? nil : a + b }.first(20)
        end
        acc
      end

      def var_values(name, state)
        return [nil] if name.nil?
        return Array(state[:vars][name]) if state[:vars].key?(name)
        case name
        when "HOME" then [@ctx.home]
        when "TMPDIR" then [TMPDIR_SENTINEL]
        when "PWD" then [state[:cwd]]
        else [nil]
        end
      end

      def cmd_value(src, state, call)
        first = src.strip.split(/\s+/).first
        cwd = shell(src, cwd: state[:cwd], call: call, vars: state[:vars])
        case first
        when "mktemp" then "#{TMPDIR_SENTINEL}/mktemp"
        when "pwd" then cwd
        end
      end

      def path_of(value, state)
        return nil if value.nil?
        # a leading ~ that survived as text (after "=" in an assignment or
        # --opt=~/x) is taken as the home: conservative, never a workspace dir
        value = value.sub(/\A~(?=\/|\z)/, @ctx.home).sub(%r{\Afile://(?:localhost)?(?=/)}i, "")
        return value if value.start_with?("/")
        return nil if state[:cwd].nil?
        File.join(state[:cwd], value)
      end

      def simple(n, state, call)
        words = n[:words]
        n[:redirs].each { |r| redirect(r, state, call) }
        # Leading NAME=value words assign (alone or as a command prefix);
        # export/local/declare/readonly assign their NAME=value operands.
        words = words.drop(1) while words.any? && assign(words.first, state, call)
        if words.any? && %w[export local declare readonly].include?(words.first.literal)
          words.drop(1).each { |w| assign(w, state, call) }
          return
        end
        command(words.map { |w| values(w, state, call) }, n, state, call) if words.any?
      end

      def assign(word, state, call)
        first = word.segs.first
        m = first && first[0] == :lit && first[1].match(/\A([A-Za-z_][A-Za-z0-9_]*)=/)
        return false unless m
        value = Word.new([[:lit, first[1].delete_prefix(m[0])]] + word.segs.drop(1), word.raw)
        state[:vars][m[1]] = values(value, state, call)
        state[:path_entries] = path_entries(value, state, call) if m[1] == "PATH"
        true
      end

      # Directories a PATH assignment adds (unresolved parts such as $PATH
      # are dropped): a bare command may be found there.
      def path_entries(word, state, call)
        text = word.segs.map do |t, v|
          case t
          when :lit then v
          when :tilde then v.empty? ? @ctx.home : "\0"
          when :var then (v && v != "PATH" && state[:vars].key?(v) ? Array(state[:vars][v]).first : nil) || "\0"
          else "\0"
          end
        end.join
        text.split(":").reject { |e| e.empty? || e.include?("\0") }.map { |e| path_of(e, state) }.compact
      end

      def redirect(r, state, call)
        case r[:op]
        when ">", ">>", ">|", "&>", "&>>", "<>"
          values(r[:target], state, call).each { |v| event("write", path_of(v, state), call, via: "redirect #{r[:op]}") }
        when "<"
          values(r[:target], state, call).each { |v| event("read", path_of(v, state), call, via: "redirect <") }
        when "<<<" then values(r[:target], state, call)
        when "<<", "<<-"
          # an unquoted heredoc body is expanded: its command substitutions run
          unless r[:quoted]
            (Lexer.substitutions(r[:body].to_s) rescue []).each { |src| shell(src, cwd: state[:cwd], call: call, vars: state[:vars]) }
          end
        when ">&", "<&"
          t = r[:target].literal
          values(r[:target], state, call).each { |v| event("write", path_of(v, state), call, via: "redirect >&") } unless t&.match?(/\A(\d+|-)\z/)
        end
      end

      def lit(argv, i) = argv[i]&.first

      def command(argv, n, state, call)
        name = lit(argv, 0)
        if name.nil?
          event("possible_read", nil, call, via: "unresolved command")
          unknown_command(argv.drop(1), state, call, via: "unresolved command")
          return
        end
        base = File.basename(name)
        unless name.include?("/")
          Array(state[:path_entries]).each do |dir|
            cand = File.join(dir, name)
            event("possible_read", cand, call, via: "command found through PATH") if UNAUTHORIZED.include?(IsolationAudit.location(cand, @ctx))
          end
        end
        known = SEMANTIC.include?(base) || base.match?(/\Apython3\.\d+\z/)
        if name.include?("/") && !known
          exec_path(name, argv, state, call)
          return
        end
        event("exec", path_of(name, state), call, via: "exec") if name.include?("/")
        if WRAPPERS.include?(base) || %w[env timeout xargs].include?(base)
          wrapped(base, argv, n, state, call)
          return
        end
        if @funcs[base]
          unknown_command(argv.drop(1), state, call, via: "function #{base}")
          return
        end
        heredoc = n[:redirs].find { |r| ["<<", "<<-"].include?(r[:op]) }&.dig(:body)
        case base
        when "cd", "pushd" then change_dir(argv, state, call)
        when "popd" then state[:cwd] = nil
        when "test", "[", "[["
          argv.each_with_index do |a, i|
            next unless i.positive? && %w[-f -d -e -r -s -x -L -h].include?(lit(argv, i - 1))
            a.each { |v| event("possible_read", path_of(v, state), call, via: "#{base} #{lit(argv, i - 1)} (existence probe)") }
          end
        when "eval"
          argv.drop(1).each do |a|
            a.each { |v| v.nil? ? event("possible_read", nil, call, via: "eval (unresolved)") : shell(v, cwd: state[:cwd], call: call, vars: state[:vars]) }
          end
        when "mktemp"
          operands(argv, "mktemp").each { |a| a.each { |v| event("write", path_of(v, state), call, via: "mktemp") if v&.include?("/") } }
        when *NO_ACCESS then nil
        when *SHELLS then shell_cmd(base, argv, heredoc, state, call)
        when *INTERPRETERS, /\Apython3\.\d+\z/ then interpreter(base, argv, heredoc, state, call)
        when "git" then git(argv, state, call)
        when "find" then find(argv, state, call)
        when "sed" then sed(argv, state, call)
        when "awk", "gawk", "mawk", "nawk" then awk(argv, state, call)
        when *PATTERN_FIRST then pattern_first(base, argv, state, call)
        when *COPIERS then copier(base, argv, state, call)
        when "ln" then ln(argv, state, call)
        when *WRITERS then operands(argv, base).each { |a| a.each { |v| event("write", path_of(v, state), call, via: base) } }
        when *MODE_WRITERS then operands(argv, base).drop(1).each { |a| a.each { |v| event("write", path_of(v, state), call, via: base) } }
        when *READERS then reader(base, argv, state, call)
        when "dd"
          argv.drop(1).each do |a|
            a.each do |v|
              next unless v
              event("read", path_of(v.delete_prefix("if="), state), call, via: "dd if=") if v.start_with?("if=")
              event("write", path_of(v.delete_prefix("of="), state), call, via: "dd of=") if v.start_with?("of=")
            end
          end
        when "tar" then tar(argv, state, call)
        else unknown_command(argv.drop(1), state, call, via: base, implicit_cwd: true)
        end
      end

      # env/timeout/xargs/sudo/... run another command. xargs supplies
      # operands from stdin, which the trace cannot resolve.
      def wrapped(base, argv, n, state, call)
        rest = argv.drop(1)
        if base == "xargs"
          # the command starts at the first operand; stdin supplies more
          rest = rest_after_options(argv, "xargs")
          rest = [["echo"]] if rest.empty?
          return command(rest + [[nil]], n, state, call)
        end
        rest = rest.drop_while do |a|
          v = a.first.to_s
          v.start_with?("-") || (base == "env" && v.match?(/\A[A-Za-z_][A-Za-z0-9_]*=/))
        end
        rest = rest.drop(1) if base == "timeout" && rest.any?
        command(rest, n, state, call) if rest.any?
      end

      # argv from the first positional operand on (a wrapped command).
      def rest_after_options(argv, base)
        with_arg = OPT_ARGS[base] || []
        i = 1
        while i < argv.size && lit(argv, i).to_s.start_with?("-") && lit(argv, i) != "-"
          v = lit(argv, i)
          i += 1 if with_arg.include?(v) && !v.include?("=")
          i += 1
        end
        argv[i..] || []
      end

      # Positional operands after options (honouring "--" and options that
      # take an argument).
      def operands(argv, base)
        with_arg = OPT_ARGS[base] || []
        out = []
        i = 1
        ended = false
        while i < argv.size
          v = lit(argv, i)
          if !ended && v == "--" then ended = true
          elsif !ended && v&.start_with?("-") && v != "-"
            flag = v.split("=", 2).first
            i += 1 if with_arg.include?(flag) && !v.include?("=")
          else out << argv[i]
          end
          i += 1
        end
        out
      end

      def opt_values(argv, flags)
        vals = []
        argv.each_with_index do |a, i|
          v = a.first
          next unless v
          flags.each do |f|
            if v == f then vals.concat(argv[i + 1] || [])
            elsif f.start_with?("--") && v.start_with?("#{f}=") then vals << v.split("=", 2).last
            elsif !f.start_with?("--") && v.start_with?(f) && v.size > f.size && v[1] != "-" then vals << v[f.size..]
            end
          end
        end
        vals
      end

      def flag?(argv, *flags)
        argv.drop(1).any? do |a|
          v = a.first.to_s
          flags.any? { |f| f.start_with?("--") ? v == f : (v.start_with?("-") && !v.start_with?("--") && v.include?(f.delete("-"))) }
        end
      end

      def pathlike?(v) = v && !v.start_with?("-") && (v.include?("/") || v.start_with?("~", "."))

      def change_dir(argv, state, call)
        target = operands(argv, "cd").first
        val = target ? target.first : @ctx.home
        path = if val == "-" then state[:prev]
               else
                 p = path_of(val, state)
                 p && IsolationAudit.norm(p)
               end
        event("cwd", path, call, via: argv.first.first)
        state[:prev] = state[:cwd]
        state[:cwd] = path
      end

      def reader(base, argv, state, call)
        ops = operands(argv, base)
        recursive = RECURSIVE.include?(base) || (base == "ls" && flag?(argv, "-R")) || (base == "diff" && flag?(argv, "-r"))
        implicit = %w[ls tree du codegraph].include?(base)
        ops = [[state[:cwd]]] if ops.empty? && implicit
        ops.each { |a| a.each { |v| event("read", path_of(v, state), call, via: base, recursive: recursive) unless v == "-" } }
      end

      def pattern_first(base, argv, state, call)
        explicit = opt_values(argv, %w[-e --regexp])
        files = opt_values(argv, %w[-f --file] + (base == "jq" ? %w[--slurpfile --rawfile] : []))
        files.each { |v| event("read", path_of(v, state), call, via: "#{base} -f") }
        ops = operands(argv, base == "egrep" || base == "fgrep" ? "grep" : base)
        no_pattern = base == "rg" && flag?(argv, "--files")
        ops = ops.drop(1) unless no_pattern || !explicit.empty? || (!files.empty? && base != "jq")
        recursive = %w[rg ag ack fd].include?(base) || flag?(argv, "-r", "-R", "--recursive")
        ops = [[state[:cwd]]] if ops.empty? && recursive
        ops.each { |a| a.each { |v| event("read", path_of(v, state), call, via: base, recursive: recursive) unless v == "-" } }
      end

      def sed(argv, state, call)
        scripts = opt_values(argv, %w[-e --expression])
        files = opt_values(argv, %w[-f --file])
        files.each { |v| event("read", path_of(v, state), call, via: "sed -f") }
        ops = operands(argv, "sed")
        ops = ops.drop(1) if scripts.empty? && files.empty?
        in_place = flag?(argv, "--in-place") || argv.drop(1).any? { |a| a.first.to_s.match?(/\A-[a-zA-Z]*i/) }
        ops.each do |a|
          a.each do |v|
            event("read", path_of(v, state), call, via: "sed")
            event("write", path_of(v, state), call, via: "sed -i") if in_place
          end
        end
      end

      def awk(argv, state, call)
        files = opt_values(argv, %w[-f])
        files.each { |v| event("read", path_of(v, state), call, via: "awk -f") }
        ops = operands(argv, "awk")
        ops = ops.drop(1) if files.empty?
        ops.each { |a| a.each { |v| event("read", path_of(v, state), call, via: "awk") unless v&.match?(/\A\w+=/) } }
      end

      def find(argv, state, call)
        paths = []
        i = 1
        while i < argv.size && !lit(argv, i).to_s.match?(/\A[-(!]/)
          paths << argv[i]
          i += 1
        end
        paths = [[state[:cwd]]] if paths.empty?
        paths.each { |a| a.each { |v| event("read", path_of(v, state), call, via: "find", recursive: true) } }
        rest = argv[i..] || []
        if rest.any? { |a| a.first == "-delete" }
          paths.each { |a| a.each { |v| event("write", path_of(v, state), call, via: "find -delete", recursive: true) } }
        end
        rest.each_with_index do |a, j|
          next unless %w[-exec -execdir -ok].include?(a.first)
          sub = rest[(j + 1)..].take_while { |x| ![";", "+", "\\;"].include?(x.first) }
          # {} is each found path: judged at the search roots
          sub = sub.map { |x| x.first == "{}" ? paths.flatten : x }
          command(sub, { redirs: [] }, copy(state), call) unless sub.empty?
        end
      end

      def copier(base, argv, state, call)
        target = opt_values(argv, %w[-t --target-directory])
        ops = operands(argv, base)
        dest = target.empty? ? ops.pop : nil
        ops.each do |a|
          a.each do |v|
            event("read", path_of(v, state), call, via: base, recursive: flag?(argv, "-R", "-r", "-a"))
            event("write", path_of(v, state), call, via: "#{base} (source)") if base == "mv"
          end
        end
        (target.map { |v| [v] } + [dest].compact).each { |a| a.each { |v| event("write", path_of(v, state), call, via: base) } }
      end

      # ln [-s] TARGET [LINK]: writes the link; later paths through the link
      # resolve to its target.
      def ln(argv, state, call)
        ops = operands(argv, "ln")
        return if ops.empty?
        target = ops.first.first
        link = ops.size >= 2 ? ops.last.first : File.basename(target.to_s)
        link_path = path_of(link, state)
        event("write", link_path, call, via: "ln")
        return unless target && link_path
        tpath = target.start_with?("/") ? target : File.join(File.dirname(link_path), target)
        @links[IsolationAudit.norm(link_path)] = IsolationAudit.norm(tpath)
      end

      def tar(argv, state, call)
        dir = opt_values(argv, %w[-C]).first
        base_dir = dir ? path_of(dir, state) : state[:cwd]
        archive = opt_values(argv, %w[-f]).first
        mode = argv[1]&.first.to_s
        create = mode.include?("c")
        event(create ? "write" : "read", path_of(archive, state), call, via: "tar -f") if archive
        if create
          operands(argv, "tar").each { |a| a.each { |v| event("read", path_of(v, { cwd: base_dir }), call, via: "tar", recursive: true) } }
        elsif mode.include?("x")
          event("write", base_dir, call, via: "tar -x", recursive: true)
        end
      end

      # git reads the repository it runs on: the cwd or -C location (its own
      # location only: git looks for .git there), --git-dir/--work-tree and
      # GIT_DIR/GIT_WORK_TREE, the sources of clone/fetch/pull/remote/
      # submodule/worktree and diff --no-index operands. Search patterns
      # (grep, log -S/-G/--grep) are data; other path operands are pathspecs,
      # which git confines to the repository: possible reads at most.
      GIT_SOURCE_SUBS = %w[clone fetch pull remote submodule worktree ls-remote fetch-pack archive].freeze
      GIT_URL_KEY = /\A(?:remote\.[^=]+\.(?:url|pushurl)|url\.[^=]+\.(?:insteadof|pushinsteadof))=/i

      def git(argv, state, call)
        repo = state[:cwd]
        env = %w[GIT_DIR GIT_WORK_TREE].filter_map { |k| var_values(k, state).first }
        extra = env.map { |v| path_of(v, state) }
        i = 1
        while i < argv.size && lit(argv, i).to_s.start_with?("-")
          key, val = lit(argv, i).to_s.split("=", 2)
          if %w[-C --git-dir --work-tree].include?(key)
            val ||= lit(argv, i += 1)
            key == "-C" ? (repo = path_of(val, { cwd: repo })) : (extra << path_of(val, { cwd: repo }))
          elsif key == "-c"
            cfg = lit(argv, i += 1).to_s
            extra_src = cfg.sub(GIT_URL_KEY, "") if cfg.match?(GIT_URL_KEY)
            (sources ||= []) << extra_src if extra_src
            name = cfg[/\Aremote\.([^=]+)\.url=/i, 1]
            @remotes[name] = extra_src if name
          end
          i += 1
        end
        sub = lit(argv, i)
        return if sub.nil? || %w[--version version help].include?(sub)
        Array(sources).each { |v| event("read", path_of(v, state), call, via: "git -c remote url", recursive: true) if pathlike?(v) || v.match?(%r{\Afile:}i) }
        event("read", repo, call, via: "git #{sub} (repository)")
        extra.uniq.each { |r| event("read", r, call, via: "git #{sub} (git dir / work tree)", recursive: true) }
        rest = argv[(i + 1)..] || []
        ops = operands([["git"]] + rest, "git")
        if sub == "grep" && opt_values(rest.map { |a| a }.unshift(["git"]), %w[-e -f]).empty?
          ops = ops.drop(1) # the pattern
        end
        if sub == "diff" && rest.any? { |a| a.first == "--no-index" }
          ops.each { |a| a.each { |v| event("read", path_of(v, state), call, via: "git diff --no-index", recursive: true) } }
        elsif GIT_SOURCE_SUBS.include?(sub)
          ops.pop.each { |v| event("write", path_of(v, state), call, via: "git clone (destination)", recursive: true) } if sub == "clone" && ops.size >= 2
          if sub == "remote" && %w[add set-url].include?(lit(ops, 0))
            name = lit(ops, 1)
            @remotes[name] = lit(ops, 2) if name
          end
          ops.each do |a|
            a.each do |v|
              if v && (pathlike?(v) || v.match?(%r{\Afile:}i))
                event("read", path_of(v, state), call, via: "git #{sub} source", recursive: true)
              elsif v && @remotes.key?(v)
                event("read", path_of(@remotes[v], state), call, via: "git #{sub} remote #{v}", recursive: true) if pathlike?(@remotes[v].to_s) || @remotes[v].to_s.match?(%r{\Afile:}i)
              elsif v && %w[fetch pull ls-remote fetch-pack].include?(sub) && v == a.first && ops.first.equal?(a)
                # a named remote this run did not visibly configure
                event("possible_read", nil, call, via: "git #{sub} remote #{v} (url not tracked)")
              end
            end
          end
          opt_values([["git"]] + rest, %w[--reference --separate-git-dir --remote]).each do |v|
            event("read", path_of(v, state), call, via: "git #{sub} #{v}", recursive: true)
          end
        elsif sub == "config"
          # git config remote.X.url <path>: remembered for later fetches
          key = lit(ops, 0).to_s
          name = key[/\Aremote\.(.+)\.url\z/i, 1]
          @remotes[name] = lit(ops, 1) if name
          ops.drop(1).each { |a| a.each { |v| event("possible_read", path_of(v, state), call, via: "git config value") if v && (pathlike?(v) || v.match?(%r{\Afile:}i)) } }
        else
          ops.each { |a| a.each { |v| event("possible_read", path_of(v, state), call, via: "git #{sub} pathspec") if pathlike?(v) } }
        end
        event("write", repo, call, via: "git #{sub}") if GIT_WRITE.include?(sub) && sub != "clone"
      end

      def shell_cmd(base, argv, heredoc, state, call)
        c_idx = argv.index { |a| a.first.to_s.match?(/\A-[a-z]*c[a-z]*\z/) }
        if c_idx
          srcs = argv[c_idx + 1] || [nil]
          srcs.each { |src| src.nil? ? event("possible_read", nil, call, via: "#{base} -c (unresolved)") : shell(src, cwd: state[:cwd], call: call, vars: state[:vars]) }
          return
        end
        ops = operands(argv, base)
        script = ops.first
        if script && script.first != "-"
          script.each { |v| exec_path(v, [[v]] + ops.drop(1), state, call, via: base) }
        elsif heredoc
          shell(heredoc, cwd: state[:cwd], call: call, vars: state[:vars])
        end
      end

      def interpreter(base, argv, heredoc, state, call)
        prog_flags = { "python" => "-c", "python2" => "-c", "python3" => "-c", "ruby" => "-e", "node" => "-e", "perl" => "-e",
                       "php" => "-r", "osascript" => "-e", "swift" => "-e" }
        flag = prog_flags[base] || "-c"
        idx = argv.index { |a| a.first == flag }
        if idx
          (argv[idx + 1] || [nil]).each { |prog| opaque(prog.to_s, call, via: "#{base} #{flag} program", unresolved: prog.nil?) }
          return
        end
        return if base.start_with?("python") && argv.any? { |a| a.first == "-m" }
        ops = operands(argv, base)
        script = ops.first
        if script && script.first != "-"
          script.each { |v| exec_path(v, [[v]] + ops.drop(1), state, call, via: base) }
        elsif heredoc
          opaque(heredoc, call, via: "#{base} stdin program")
        end
      end

      # Running a program file reads it: judged like any read (a script at a
      # host path executed under bash -x prints itself). What the program
      # reads in turn is not observable; its arguments are judged like an
      # unknown command's.
      def exec_path(value, argv, state, call, via: "exec")
        path = path_of(value, state)
        event("exec", path, call, via: via)
        event("read", path, call, via: "#{via} (program file)")
        unknown_command(argv.drop(1), state, call, via: "#{via} args")
      end

      # Unknown programs: an operand (or --opt=value) that names a path in a
      # host or protected location, or cannot be resolved, may be read; bare
      # names are data.
      def unknown_command(args, state, call, via:, implicit_cwd: false)
        args.each do |a|
          a.each do |v|
            v = v.split("=", 2).last if v&.start_with?("--") && v.include?("=")
            if v.nil?
              event("possible_read", nil, call, via: "#{via} (unresolved operand)")
              next
            end
            next unless pathlike?(v)
            path = path_of(v, state)
            loc = IsolationAudit.location(through_links(path), @ctx)
            event("possible_read", path, call, via: via) if UNAUTHORIZED.include?(loc) || loc == "unknown"
          end
        end
        loc = IsolationAudit.location(state[:cwd], @ctx)
        event("possible_read", state[:cwd], call, via: "#{via} (cwd)") if implicit_cwd && (UNAUTHORIZED.include?(loc) || loc == "unknown")
      end

      # Code we cannot interpret (python -c, heredoc programs, unparsable
      # shell): absolute or ~ path literals in an unauthorized location are
      # possible reads, never more; an unresolved program is itself one.
      def opaque(text, call, via:, unresolved: false)
        event("possible_read", nil, call, via: "#{via} (unresolved)") if unresolved
        text.to_s.scan(/(?:\A|(?<=[\s'"=(,\[{:]))((?:~|\/)[A-Za-z0-9_.@%+\-\/*?]*)/).flatten.uniq.each do |tok|
          path = tok.start_with?("~") ? tok.sub(/\A~/, @ctx.home) : tok
          next if path == "/"
          loc = IsolationAudit.location(through_links(path), @ctx)
          event("possible_read", path, call, via: via) if UNAUTHORIZED.include?(loc)
        end
      end
    end

    # ------------------------------------------------------------ traces

    # Normalised tool calls: {index, tool, input, output, error, exit_code,
    # workdir, rejected}.
    def self.claude_calls(events)
      results = {}
      not_run = {}
      events.select { |e| e["type"] == "user" }.each do |e|
        # Claude Code marks a tool call it did not execute (a hook or permission
        # denial) beside the result, outside anything a command can print.
        Array(e["tool_result_meta"]).each { |m| not_run[m["id"]] = m["non_execution_kind"] if m.is_a?(Hash) }
        Array(e.dig("message", "content")).each do |c|
          next unless c.is_a?(Hash) && c["type"] == "tool_result"
          text = c["content"].is_a?(Array) ? c["content"].map { |x| x["text"].to_s }.join : c["content"].to_s
          results[c["tool_use_id"]] = { output: text, error: c["is_error"] == true }
        end
      end
      calls = []
      events.select { |e| e["type"] == "assistant" }.each do |e|
        Array(e.dig("message", "content")).each do |c|
          next unless c.is_a?(Hash) && c["type"] == "tool_use"
          r = results[c["id"]] || {}
          # A call the runtime did not execute (the read-only Bash guard's
          # PreToolUse denial) never ran: the same standing as a Codex sandbox
          # rejection. Decided by the runtime's own marker, never by output text,
          # and only for the kind known to mean "refused before it started": any
          # other kind could mark a call that partly ran.
          rejected = not_run[c["id"]] == "permission-rule"
          calls << { index: calls.size, tool: c["name"], input: c["input"].is_a?(Hash) ? c["input"] : {}, output: r[:output].to_s, error: r[:error],
                     rejected: rejected }
        end
      end
      calls
    end

    CODEX_AUDITED_TOOLS = %w[exec_command apply_patch write_stdin].freeze
    CODEX_IGNORED_TOOLS = %w[exec update_plan].freeze # exec: code-mode wrapper whose tool calls are logged themselves

    # Codex tool calls from codex.log (exact command, workdir, exit code, and
    # commands the sandbox rejected), plus events.jsonl output for the
    # exposure check. Without codex.log, events.jsonl display commands are
    # used and coverage is incomplete (no workdir).
    def self.codex_calls(codex_dir)
      log = File.join(codex_dir, "codex.log")
      events = File.join(codex_dir, "events.jsonl")
      extra_output = File.exist?(events) ? File.foreach(events).filter_map { |l| (JSON.parse(l) rescue nil)&.dig("item", "aggregated_output") }.join("\n") : ""
      coverage = { "source" => "codex.log", "complete" => true, "notes" => [] }
      calls = []
      if File.exist?(log)
        entries = File.read(log, encoding: "UTF-8").scrub.split(/^(?=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+Z\s+[A-Z]+ )/)
        entries.each do |e|
          next unless e.include?('event.name="codex.tool_result"') && e.include?(" arguments=")
          tool = e[/ tool_name=([\w.-]+)/, 1]
          next if CODEX_IGNORED_TOOLS.include?(tool)
          unless CODEX_AUDITED_TOOLS.include?(tool)
            coverage["complete"] = false
            coverage["notes"] << "unaudited tool #{tool}"
            next
          end
          case tool
          when "exec_command", "write_stdin"
            args, args_end = json_after(e, " arguments=")
            output = codex_output(args_end ? e[args_end..].to_s.split(" output=", 2)[1].to_s : "")
            rejected = e.include?("success=false") && output.match?(/\Aexec_command failed: CreateProcess.*Rejected\(/m)
            unless args
              coverage["complete"] = false
              coverage["notes"] << "unparsable #{tool} arguments"
              next
            end
            cmd = tool == "write_stdin" ? args["chars"].to_s : args["cmd"].to_s
            # the logged output starts with a header (Chunk ID, Wall time, exit
            # code, token count, "Output:"); the command's own output follows it
            body = output[/^Original token count: 0$/] ? "" : (output.split(/^Output:\n/, 2)[1] || output)
            calls << { index: calls.size, tool: "exec", input: { "command" => cmd }, output: output, body: body,
                       workdir: tool == "write_stdin" ? :unknown : args["workdir"],
                       exit_code: output[/Process exited with code (\d+)/, 1]&.to_i, rejected: rejected, error: rejected }
          when "apply_patch"
            body = e.split(" arguments=", 2)[1].to_s
            cut = body.index("*** End Patch") || 0
            patch = body[0...cut]
            output = codex_output(body[cut..].to_s.split(" output=", 2)[1].to_s)
            rejected = false
            targets = patch.scan(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/).flatten + patch.scan(/^\*\*\* Move to: (.+)$/).flatten
            ok = output.match?(/Exit code: 0|Success/)
            calls << { index: calls.size, tool: "file_change", input: { "changes" => targets.map { |t| { "path" => t.strip, "kind" => "patch" } } },
                       output: output, error: !ok, rejected: rejected }
          end
        end
      elsif File.exist?(events)
        coverage = { "source" => "events.jsonl", "complete" => false, "notes" => ["codex.log missing: display commands, workdir unknown"] }
        File.foreach(events) do |l|
          e = (JSON.parse(l) rescue nil)
          next unless e && e["type"] == "item.completed" && e["item"].is_a?(Hash)
          it = e["item"]
          case it["type"]
          when "command_execution"
            calls << { index: calls.size, tool: "exec", input: { "command" => it["command"] }, output: it["aggregated_output"].to_s,
                       exit_code: it["exit_code"], error: it["exit_code"] != 0 }
          when "file_change"
            calls << { index: calls.size, tool: "file_change", input: { "changes" => it["changes"] }, output: "", error: it["status"] != "completed" }
          end
        end
      else
        return nil
      end
      # Cross-check: every command and patch events.jsonl saw must have been
      # audited from the log (a renamed log event would otherwise pass clean).
      if File.exist?(log) && File.exist?(events)
        seen = Hash.new(0)
        File.foreach(events) do |l|
          ev = (JSON.parse(l) rescue nil)
          seen[ev.dig("item", "type")] += 1 if ev && ev["type"] == "item.completed"
        end
        execs = calls.count { |c| c[:tool] == "exec" && !c[:rejected] }
        patches = calls.count { |c| c[:tool] == "file_change" }
        if seen["command_execution"] > execs || seen["file_change"] > patches
          coverage["complete"] = false
          coverage["notes"] << "events.jsonl has #{seen['command_execution']} commands / #{seen['file_change']} patches; log yielded #{execs} / #{patches}"
        end
      end
      calls << { index: calls.size, tool: "output", input: {}, output: extra_output } unless extra_output.empty?
      [calls, coverage]
    end

    # Claude reports an empty Bash result as a placeholder, and a failed one
    # with a leading "Exit code N" line: neither is the command's output.
    def self.claude_body(out)
      out.to_s.sub(/\A\(Bash completed with no output\)\s*\z/, "").sub(/\AExit code \d+\s*/, "")
    end

    # A logged tool output without the log record's trailing fields
    # (" mcp_server= ... event.timestamp= ... slug=...").
    def self.codex_output(text)
      cut = text.rindex(/\s+mcp_server=\S*\s+mcp_server_origin=/)
      cut ? text[0...cut] : text
    end

    # The JSON object that starts right after marker in text, and the index
    # just past it.
    def self.json_after(text, marker)
      i = text.index("#{marker}{") or return [nil, nil]
      i += marker.size
      depth = 0
      instr = false
      j = i
      while j < text.size
        c = text[j]
        if instr
          if c == "\\" then j += 1
          elsif c == '"' then instr = false
          end
        elsif c == '"' then instr = true
        elsif c == "{" then depth += 1
        elsif c == "}"
          depth -= 1
          return [(JSON.parse(text[i..j]) rescue nil), j + 1] if depth.zero?
        end
        j += 1
      end
      [nil, nil]
    end

    # ------------------------------------------------------------ audit

    def self.audit(host:, calls:, workspace:, policy:, enforce:, canaries: [], protected_roots: [], coverage: nil)
      ws = norm(File.exist?(workspace) ? File.realpath(workspace) : workspace)
      home = norm(File.realpath(Dir.home))
      ctx = Ctx.new(host: host, workspace: ws, home: home, protected: protected_roots.map { |r| norm(r) }.uniq,
                    enforce: enforce, policy: policy || {})
      ev = Evaluator.new(ctx)
      claude_cwd = ws
      calls.each do |call|
        input = call[:input]
        case call[:tool]
        when "Bash"
          final = ev.shell(input["command"].to_s, cwd: claude_cwd, call: call)
          # Claude Code keeps the shell cwd inside the workspace and resets it otherwise.
          claude_cwd = final && within?(final, ws) ? final : ws
        when "exec"
          wd = call[:workdir]
          cwd = if wd == :unknown then nil
                elsif wd then norm(abs(wd, ws))
                else ws
                end
          ev.event("cwd", cwd, call, via: "workdir") if cwd.nil? || !within?(cwd, ws)
          ev.shell(input["command"].to_s, cwd: cwd, call: call)
        when "Read", "NotebookRead"
          ev.event("read", abs(input["file_path"] || input["notebook_path"], ws), call, via: "file tool #{call[:tool]}")
        when "Grep", "Glob", "LS"
          base = abs(input["path"] || ws, ws)
          pat = input["pattern"].to_s
          base = abs(pat, ws) if call[:tool] == "Glob" && pat.start_with?("/", "~")
          ev.event("read", base, call, via: "file tool #{call[:tool]}", recursive: call[:tool] != "LS")
        when "Edit", "Write", "MultiEdit", "NotebookEdit"
          ev.event("write", abs(input["file_path"] || input["notebook_path"], ws), call, via: "file tool #{call[:tool]}")
        when "file_change"
          Array(input["changes"]).each { |ch| ev.event("write", abs(ch["path"], ws), call, via: "apply_patch #{ch['kind']}") }
        end
      end
      events = ev.events.map { |e| e.merge("status" => status(e, ctx)) }
      build(events, calls, ctx, canaries, ev.unparsed, coverage)
    end

    def self.abs(path, ws)
      return nil if path.nil?
      p = path.to_s.sub(/\A~(?=\/|\z)/, Dir.home)
      p.start_with?("/") ? p : File.join(ws, p)
    end

    # An error in the call's output that names this exact path.
    def self.error_names?(call, path)
      return false if path.nil?
      out = call[:output].to_s
      [path, norm(path)].uniq.any? { |p| out.each_line.any? { |l| l.include?(p) && l.match?(READ_ERROR) } }
    end

    # Status of one event. Observed results decide where the trace shows
    # them: file-tool results, Codex rejections, an error naming that path.
    # A shell read of a host path succeeded when the command exited 0 or
    # produced output; with neither, it is unknown. Claude's sandbox makes
    # the home unreadable: a literal home path read from Bash is prevented
    # (alias spellings fall through to the output evidence).
    def self.status(e, ctx)
      call = e["_call"]
      loc = e["location"]
      kind = e["kind"]
      shell = %w[Bash exec].include?(call[:tool])
      return "n/a" if %w[cwd exec].include?(kind)
      return "prevented" if call[:rejected]
      case kind
      when "read", "possible_read"
        return "allowed" unless UNAUTHORIZED.include?(loc) || %w[unknown other].include?(loc)
        if loc == "unknown"
          # An unresolved path cannot reach protected data when the home is
          # unreadable for this tool and every protected root lies under it.
          denied = shell ? ctx.enforce[:shell_home_read_denied] : ctx.enforce[:file_tool_home_denied]
          return denied && ctx.protected.all? { |r| within?(r, ctx.home) } ? "contained" : "unknown"
        end
        unless shell
          return call[:error] ? (call[:output].to_s.match?(/denied|permission|not allowed|outside/i) ? "prevented" : "failed") : (loc == "other" ? "unknown" : "succeeded")
        end
        return "prevented" if ctx.enforce[:shell_home_read_denied] && literal_home?(e["path"], ctx)
        return "failed" if !e["recursive"] && error_names?(call, e["path"])
        return "unknown" if kind == "possible_read" || loc == "other"
        exited_ok = ctx.host == "codex" ? call[:exit_code] == 0 : call[:error] == false
        # output from any part of a compound command counts (strict)
        body = call[:body] || (call[:tool] == "Bash" ? claude_body(call[:output]) : call[:output])
        exited_ok || !body.to_s.strip.empty? ? "succeeded" : "unknown"
      when "write"
        return "allowed" if loc == "workspace" || loc == "device" || (loc == "scratch" && ctx.policy["scratch_writes"])
        unless shell
          return call[:error] ? "prevented" : "succeeded"
        end
        enforced = ctx.enforce[:shell_write_roots]
        if loc == "unknown"
          # Enforced write roots confine an unresolved path to allowed places
          # unless scratch is enforced-writable but not allowed by the task.
          ok = enforced && (enforced - %w[workspace device] - (ctx.policy["scratch_writes"] ? ["scratch"] : [])).empty?
          return ok ? "contained" : "unknown"
        end
        return "prevented" if enforced && !enforced.include?(loc)
        return "failed" if error_names?(call, e["path"])
        "succeeded"
      end
    end

    # The path as written (tilde expanded, not normalised) lies under the home.
    def self.literal_home?(path, ctx)
      return false if path.nil?
      p = File.expand_path(path, "/")
      [ctx.home, Dir.home].uniq.any? { |h| p == h || p.start_with?("#{h}/") }
    end

    def self.build(events, calls, ctx, canaries, unparsed, coverage)
      clean = events.map { |e| e.except("_call") }
      reads = clean.select { |e| %w[read possible_read].include?(e["kind"]) && e["status"] != "allowed" }
      writes = clean.select { |e| e["kind"] == "write" && e["status"] != "allowed" }
      cwd = clean.select { |e| e["kind"] == "cwd" && e["location"] != "workspace" }
      permitted = ctx.policy["cwd_independence"] && cwd.all? { |e| %w[scratch runtime].include?(e["location"]) }
      visible = calls.map { |c| c[:output].to_s }.join("\n")
      hits = canaries.select { |c| visible.include?(c[:line]) }
      mentions = calls.flat_map do |c|
        s = JSON.generate(c[:input])
        LEGACY_MARKERS.select { |m| s.include?(m) }.map { |m| { "call" => c[:index], "marker" => m } }
      end
      dim = ->(list) { list.any? { |e| e["status"] == "succeeded" } ? "observed" : list.any? { |e| e["status"] == "unknown" } ? "unknown" : "none" }
      read_status = dim.call(reads)
      read_status = "unknown" if read_status == "none" && coverage && !coverage["complete"]
      {
        "version" => VERSION,
        "external_read" => { "status" => read_status, "events" => reads.first(20) },
        "external_write" => { "status" => dim.call(writes), "events" => writes.first(20) },
        "reference_exposure" => { "status" => hits.empty? ? "none" : "observed", "canaries_checked" => canaries.size,
                                  "matches" => hits.first(5).map { |h| { "file" => h[:file], "line" => h[:line][0, 80] } } },
        "cwd_escape" => { "occurred" => !cwd.empty?, "permitted_by_task" => cwd.empty? || permitted ? true : false,
                          "events" => cwd.first(10).map { |e| e.slice("call", "path", "location", "via") } },
        "executed_outside" => clean.select { |e| e["kind"] == "exec" && UNAUTHORIZED.include?(e["location"]) }.first(10)
                                   .map { |e| e.slice("call", "path", "location", "via") },
        "scratch" => { "reads" => clean.count { |e| e["kind"] == "read" && e["location"] == "scratch" },
                       "writes" => clean.count { |e| e["kind"] == "write" && e["location"] == "scratch" } },
        "path_string_mentions" => { "count" => mentions.size, "examples" => mentions.first(5), "note" => "diagnostic only" },
        "unparsed_commands" => unparsed, "calls_audited" => calls.count { |c| c[:tool] != "output" }, "coverage" => coverage,
        "enforcement" => ctx.enforce.transform_keys(&:to_s), "policy" => ctx.policy
      }.compact
    end

    # The run is contaminated only by an observed unauthorized read, write or
    # reference exposure.
    def self.suspect?(audit)
      %w[external_read external_write reference_exposure].any? { |k| audit.dig(k, "status") == "observed" }
    end

    # ------------------------------------------------------------ run records

    # Hidden reference lines (MIN_CANARY+ chars) that occur nowhere in the
    # task's workspace export or packet and are not a bare path: if one shows
    # up in model-visible tool output, reference data reached the model
    # whatever the channel.
    def self.canaries_for(task)
      @canaries ||= {}
      @canaries[task.id] ||= Dir.mktmpdir("eval-canary-") do |tmp|
        ws, = Evals.prepare_workspace(task, tmp)
        files = Dir.glob("**/*", File::FNM_DOTMATCH, base: ws).reject { |p| p == ".git" || p.start_with?(".git/") }
        corpus = files.map { |p| File.join(ws, p) }.select { |p| File.file?(p) }
                      .map { |p| File.binread(p).force_encoding(Encoding::UTF_8).scrub }.join("\n") + task.packet_text
        Evals.hidden_roots.flat_map { |h| Dir.glob(File.join(h, "**", "*")) }.select { |f| File.file?(f) }.sort.flat_map do |f|
          File.read(f, encoding: "UTF-8").lines.map(&:strip)
              .select { |l| l.size >= MIN_CANARY && !corpus.include?(l) && !l.sub(/\A-\s+/, "").delete("'\"").match?(%r{\A[\w.@/-]+\z}) }.uniq
              .map { |l| { file: Evals.data_roots.reduce(f) { |p, root| p.delete_prefix("#{root}/") }, line: l } }
        end
      end
    end

    def self.protected_roots
      [Evals::ROOT, Evals::REPO, Evals.store].compact + Hash(Evals.config["repos"]).keys.map { |k| Evals.repo_path(k) }
    end

    # Workspace of a run: recorded, else the harness workspace path
    # (".../eval-ws-*/workspace") found in its command or trace.
    def self.workspace_of(run_dir, rec)
      return rec["workspace"] if rec["workspace"]
      sources = [File.join(run_dir, "command.json"), File.join(run_dir, "artifacts", "claude-stream.jsonl"),
                 File.join(run_dir, "artifacts", "codex", "events.jsonl"), File.join(run_dir, "artifacts", "codex", "codex.log")]
      sources.each do |f|
        next unless File.exist?(f)
        m = File.read(f, encoding: "UTF-8").scrub.match(%r{(/(?:private/)?var/folders/[^\s"']+?/eval-ws-[A-Za-z0-9-]+/workspace)(?=[/"'\s]|\z)})
        return m[1] if m
      end
      nil
    end

    # What the runtime enforced for this run, from its saved command (Claude)
    # or the observed Codex sandbox. Only shell enforcement is used for
    # status; file-tool results are observed per call.
    def self.enforcement_of(run_dir, rec)
      if rec["host"] == "claude-code"
        argv = (JSON.parse(File.read(File.join(run_dir, "command.json")))["argv"] rescue nil) || []
        i = argv.index("--settings")
        st = (i && JSON.parse(argv[i + 1]) rescue nil) || {}
        sandbox = st.dig("sandbox", "enabled") == true && st.dig("sandbox", "allowUnsandboxedCommands") == false
        deny = Array(st.dig("permissions", "deny"))
        { shell_home_read_denied: sandbox && Array(st.dig("sandbox", "filesystem", "denyRead")).include?("~"),
          file_tool_home_denied: deny.include?("Read(~/**)") && deny.include?("Grep(~/**)") && deny.include?("Glob(~/**)"),
          shell_write_roots: sandbox ? %w[workspace scratch device] : nil }
      else
        roots = case rec.dig("tool_profile", "sandbox")
                when "read-only" then %w[device]
                when "workspace-write" then %w[workspace scratch device]
                end
        { shell_home_read_denied: false, file_tool_home_denied: false, shell_write_roots: roots }
      end
    end

    # [calls, coverage] for a stored run, or nil when its trace is missing.
    def self.calls_of(run_dir, rec)
      if rec["host"] == "claude-code"
        stream = File.join(run_dir, "artifacts", "claude-stream.jsonl")
        File.exist?(stream) ? [claude_calls(Evals.parse_stream(stream)), { "source" => "claude stream", "complete" => true, "notes" => [] }] : nil
      else
        codex_calls(File.join(run_dir, "artifacts", "codex"))
      end
    end

    # Full audit of a stored run; nil when its trace or workspace is missing
    # (the run is then not valid evidence: nothing can vouch for it).
    def self.for_run(run_dir, rec, task)
      calls, coverage = calls_of(run_dir, rec)
      ws = workspace_of(run_dir, rec)
      return nil unless calls && ws
      audit(host: rec["host"], calls: calls, workspace: ws, policy: task["eval_policy"] || {}, enforce: enforcement_of(run_dir, rec),
            canaries: canaries_for(task), protected_roots: protected_roots, coverage: coverage)
    end

    def self.contamination_summary(audit)
      return { "suspect" => true, "basis" => VERSION, "evidence" => ["isolation audit unavailable: trace or workspace missing"] } unless audit
      evidence = %w[external_read external_write].flat_map do |k|
        audit[k]["events"].select { |e| e["status"] == "succeeded" }.map { |e| "#{k}: #{e['kind']} #{e['path']} (#{e['location']}, via #{e['via']})" }
      end
      evidence += audit["reference_exposure"]["matches"].map { |m| "reference_exposure: #{m['file']}: #{m['line']}" }
      { "suspect" => suspect?(audit), "basis" => VERSION, "evidence" => evidence.first(5) }
    end
  end
end
