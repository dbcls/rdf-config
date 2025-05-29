def change_value(v, *args)
  default_v = if args.last.is_a?(Array)
                args.pop
              else
                v.to_s
              end

  mapped_v = nil
  args.each do |arg|
    ary = JSON.parse(arg)
    if v.to_s == ary[0].to_s
      mapped_v = ary[1].to_s
      break
    end
  end

  mapped_v.nil? ? default_v : mapped_v
end
