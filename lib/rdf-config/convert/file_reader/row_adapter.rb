# frozen_string_literal: true

class RowAdapter
  def initialize(header, fields)
    @header = header
    @fields = fields
    @index ||= nil
  end

  def [](key)
    build_index! unless @index
    idx = @index[key]
    return nil unless idx
    @fields[idx]
  end

  def fetch(key, default = nil)
    v = self[key]
    v.nil? ? default : v
  end

  def to_h
    build_index! unless @index
    h = {}
    @header.each_with_index do |name, i|
      h[name] = @fields[i]
    end
    h
  end

  def empty?
    false
  end

  private

  def build_index!
    @index = {}
    @header.each_with_index do |name, i|
      @index[name] = i
    end
  end
end
