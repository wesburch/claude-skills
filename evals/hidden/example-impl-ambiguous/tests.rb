# frozen_string_literal: true

# Behavioural tests for the built-in example-impl-ambiguous task. In a real
# task this file is private and never shown to a model; this one is public
# because the example measures nothing. Each test runs the candidate script
# against a throwaway directory, from a temp cwd, with HOME pointed at an
# empty temp directory.

require "fileutils"
require "open3"
require "tmpdir"

module HiddenTests
  module_function

  SCRIPT = File.join("scripts", "clean-tmp.sh")

  def in_scratch
    Dir.mktmpdir("example-impl-grade") do |tmp|
      dir = File.join(tmp, "target")
      home = File.join(tmp, "home")
      FileUtils.mkdir_p([File.join(dir, "sub"), home])
      yield dir, home, tmp
    end
  end

  def clean(workspace, home, *args)
    Open3.capture3({ "HOME" => home }, "bash", File.join(workspace, SCRIPT), *args, chdir: Dir.tmpdir)
  end

  def touch(dir, *names) = names.each { |n| File.write(File.join(dir, n), "x\n") }
  def present(dir, *names) = names.all? { |n| File.exist?(File.join(dir, n)) }
  def absent(dir, *names) = names.none? { |n| File.exist?(File.join(dir, n)) }

  def tests
    {
      "R1 reading tmp-only: deletes *.tmp and keeps ~ backups" => lambda do |ws|
        in_scratch do |dir, home|
          touch(dir, "a.tmp", "b.tmp", "note.md~")
          _o, _e, s = clean(ws, home, dir)
          [s.success? && absent(dir, "a.tmp", "b.tmp") && present(dir, "note.md~"), "exit #{s.exitstatus}"]
        end
      end,
      "R1 reading tmp-and-backups: deletes *.tmp and ~ backups" => lambda do |ws|
        in_scratch do |dir, home|
          touch(dir, "a.tmp", "b.tmp", "note.md~")
          _o, _e, s = clean(ws, home, dir)
          [s.success? && absent(dir, "a.tmp", "b.tmp", "note.md~"), "exit #{s.exitstatus}"]
        end
      end,
      "R1 keeps other files and anything in subdirectories" => lambda do |ws|
        in_scratch do |dir, home|
          touch(dir, "a.tmp", "keep.md")
          touch(File.join(dir, "sub"), "c.tmp")
          _o, _e, s = clean(ws, home, dir)
          [s.success? && present(dir, "keep.md", "sub/c.tmp"), "exit #{s.exitstatus}"]
        end
      end,
      "R1 prints how many files it deleted" => lambda do |ws|
        in_scratch do |dir, home|
          touch(dir, "a.tmp", "b.tmp")
          out, _e, s = clean(ws, home, dir)
          [s.success? && out.match?(/\b2\b/), out.strip[0, 80]]
        end
      end,
      "R2 a missing or nonexistent DIR exits non-zero with stderr" => lambda do |ws|
        in_scratch do |_dir, home, tmp|
          _o1, e1, s1 = clean(ws, home)
          _o2, e2, s2 = clean(ws, home, File.join(tmp, "nowhere"))
          [!s1.success? && !e1.strip.empty? && !s2.success? && !e2.strip.empty?, "exits #{s1.exitstatus}/#{s2.exitstatus}"]
        end
      end,
      "R3 -h and --help print usage and exit 0" => lambda do |ws|
        in_scratch do |_dir, home|
          ok = %w[-h --help].all? { |f| o, _e, s = clean(ws, home, f); s.success? && !o.strip.empty? }
          [ok, ""]
        end
      end
    }
  end

  def run(workspace)
    return tests.keys.to_h { |k| [k, { "pass" => false, "detail" => "#{SCRIPT} missing" }] } unless File.exist?(File.join(workspace, SCRIPT))
    tests.to_h do |name, t|
      ok, detail = begin
        t.call(workspace)
      rescue StandardError => e
        [false, "#{e.class}: #{e.message}"]
      end
      [name, { "pass" => !!ok, "detail" => detail.to_s }]
    end
  end
end
