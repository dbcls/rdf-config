require_relative 'replace'

def delete(v, *args)
  replace(v, args[0], '')
end
