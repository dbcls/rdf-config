def replace(v, *args)
  pattern = args[0]
  replace_value = args[1]
  if /\A\/(.+)\/([a-z]*)\z/ =~ pattern
    if $2.to_s.empty?
      pattern = Regexp.compile($1)
      v.to_s.sub(pattern, replace_value)
    else
      regexp_ops = $2.split('')
      pattern = if regexp_ops.include?('i')
                  Regexp.compile($1, Regexp::IGNORECASE)
                else
                  Regexp.compile($1)
                end

      if regexp_ops.include?('g')
        v.to_s.gsub(pattern, replace_value)
      else
        v.to_s.sub(pattern, replace_value)
      end
    end
  else
    v.to_s.sub(pattern, replace_value)
  end
end
