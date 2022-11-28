def json(v, *args)
  v[args[0].split(%r{\s*/\s*}).last]
end
