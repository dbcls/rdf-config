def xml(v, *args)
  last_separator_pos = args[0].rindex('/')
  return v if last_separator_pos.nil?

  xpath = args[0][..last_separator_pos - 1]
  v.get_elements(xpath).first
end
