def change_value(v, *args)
  mapped_v = v.to_s
  args.each do |arg|
    ary = eval(arg)
    if mapped_v == ary[0].to_s
      mapped_v = ary[1].to_s
      break
    end
  end

  mapped_v
end
