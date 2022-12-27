def xml(v, *args)
  case args[0]
  when 'attribute'
    # v.attribute(args[1]).to_s
    v.attribute(args[1]).value
  when 'text'
    v.get_elements(args[1]).first.text
  end
end
