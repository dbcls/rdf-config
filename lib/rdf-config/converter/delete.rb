def delete(v, *args)
    if args[0][0] == '/'
        pattern = Regexp.compile(args[0][1..-2])
    else
        pattern = args[0][1..-2]
    end
    v.gsub(pattern, '')
end
