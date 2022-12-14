def to_bool(v, *args)
  !%w[0 f false].include?(v.to_s.downcase)
end
