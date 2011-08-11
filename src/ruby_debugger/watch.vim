" *** Watch class - it's exactly like a var execpt
" it operates in a different window

let s:Watch = copy(s:Var)

function! s:Watch.new(attrs)
  let new_watch = copy(Var.new(attrs))
  let new_watch.current = "current_watch"
  return new_watch
endfunction

function! s:Watch.get_selected()
  let line = getline(".") 
  " Get its id - it is last in the string
  let match = matchlist(line, '.*\t\(\d\+\)$') 
  let id = get(match, 1)
  if id
    let variable = g:RubyDebugger.watches.find_variable({'id' : id})
    return variable
  else
    return {}
  endif 
endfunction

" *** Watch Proxy class (end)

