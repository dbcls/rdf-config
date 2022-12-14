def json(v, *args)
  case v
  when Hash
    v[args[0]]
  when Array
    v.map { |h| h[args[0]] }
  else
    v
  end
end
