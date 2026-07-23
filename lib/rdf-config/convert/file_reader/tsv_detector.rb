# frozen_string_literal: true

# Heuristically determines whether a .txt file is in TSV (tab-separated values) format.
#
# Criteria:
#   1. It is a text file (no NUL bytes and no invalid byte sequences).
#   2. Every sampled line contains a tab.
#   3. The field count is consistent across lines and is 2 or more.
class TsvDetector
  SAMPLE_LINES = 100             # Number of leading lines used for detection.
  ENCODING     = "UTF-8"         # Expected character encoding (change if needed).

  # Detection result. `reason` is nil when the file is judged to be a TSV.
  Result = Struct.new(:tsv, :reason) do
    def tsv? = tsv
  end

  def initialize(path, sample_lines: SAMPLE_LINES, encoding: ENCODING)
    @path = path
    @sample_lines = sample_lines
    @encoding = encoding
  end

  # Returns a Result describing whether the file is a TSV and, if not, why.
  def detect
    return failure("not a regular file") unless File.file?(@path)
    return failure("file is empty") if File.zero?(@path)

    lines, read_error = sample_lines
    return failure(read_error) if read_error
    return failure("no readable lines") if lines.empty?

    # Every line must contain at least one tab.
    no_tab = lines.index { |line| !line.include?("\t") }
    if no_tab
      return failure("line #{no_tab + 1} contains no tab character")
    end

    # Field counts must be consistent. Every line is guaranteed to contain a
    # tab (checked above), so each count is already 2 or more.
    counts = lines.map { |line| line.split("\t", -1).size }
    if counts.uniq.size > 1
      # Report the first line whose column count differs from line 1.
      expected = counts.first
      bad = counts.index { |c| c != expected }
      return failure(
        "inconsistent column count " \
          "(line 1 has #{expected} columns but line #{bad + 1} has #{counts[bad]})"
      )
    end

    Result.new(true, nil)
  end

  # Convenience boolean accessor.
  def tsv?
    detect.tsv?
  end

  private

  def failure(reason)
    Result.new(false, reason)
  end

  # Reads up to @sample_lines leading lines.
  # Returns [lines, nil] on success, or [[], reason] for non-text input.
  def sample_lines
    lines = []
    # Open in binary mode and validate the encoding ourselves.
    File.open(@path, "rb") do |io|
      io.each_line do |raw|
        # A NUL byte indicates a binary file.
        return [[], "binary file (contains a NUL byte)"] if raw.include?("\x00".b)

        text = raw.dup.force_encoding(@encoding)
        # An invalid byte sequence means this is not a (well-formed) text file.
        unless text.valid_encoding?
          return [[], "invalid #{@encoding} byte sequence (not a text file?)"]
        end

        lines << text.chomp   # Strip the trailing newline (LF or CRLF).
        break if lines.size >= @sample_lines
      end
    end
    [lines, nil]
  end
end

# Usage:
#   ruby tsv_detector.rb path/to/file.txt
if $PROGRAM_NAME == __FILE__
  path = ARGV[0]
  abort "usage: #{$PROGRAM_NAME} FILE.txt" unless path
  abort "file not found: #{path}" unless File.exist?(path)

  result = TsvDetector.new(path).detect
  if result.tsv?
    puts "#{path}: TSV file"
    exit 0
  else
    puts "#{path}: not a TSV file (reason: #{result.reason})"
    exit 1
  end
end
