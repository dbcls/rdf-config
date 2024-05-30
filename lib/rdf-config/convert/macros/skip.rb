def skip(v, *args)
  if args.map(&:to_s).include?(v.to_s)
    ''
  else
    v
  end
end
