" *** Watch classes (start)

let s:WatchExpression = { "id" : 0 }

function! s:WatchExpression.new(expr)
  let new_watch_expression = copy(self)
  let new_watch_expression.expr = a:expr
  let result = s:WatchResult.new({'hasChildren':'true'})
  let new_watch_expression.result = copy(result)
  let s:WatchExpression.id += 1
  let new_watch_expression.id = s:WatchExpression.id
  return new_watch_expression
endfunction

function! s:WatchExpression.delete()
  call filter(g:RubyDebugger.watch_queue.queue, "v:val.id != " . self.id) 
endfunction

function! s:WatchExpression.render()
  " in general, the root variable is not actually drawin - but draw
  " these all since there are multiple roots
  if has_key(self.result,'children')
    let var_render = self.result._render(0,1,[],len(self.result.children) ==# 1)
  else
    let var_render = self.result._render(0,1,[],0)
  endif
  let lines = substitute(var_render, '\n\(.\)', '\n      \1','g')
  let output = self.id . " => " . lines 
  return output
endfunction

function! s:WatchExpression.find_watch(watch_id)
  let root_watch = filter(copy(g:RubyDebugger.watch_queue.queue), "v:val.id == " . a:watch_id)
  return root_watch[0]
endfunction

function! s:WatchExpression.get_selected_expression()
  let linenum = line(".") 
  while linenum > 0
    let line = getline(linenum) 
    let match = matchlist(line, '^\(\d\+\)\s=>') 
    let watch_id = get(match, 1)
    if watch_id
      break
    endif
    let linenum -= 1
  endwhile

  if !watch_id
    return 0 
  endif
  return watch_id
endfunction

function! s:WatchExpression.get_selected()
  let watch_id = s:WatchExpression.get_selected_expression()
  let var_match = matchlist(getline("."),'.*\t\(\d\+\)$')
  let var_id = get(var_match,1)
  if var_id
    let watch = s:WatchExpression.find_watch(watch_id)
    let variable = watch.result.find_variable({'id':var_id})
    return variable
  else
    return {}
  endif 
endfunction

" *** Watch class - this is exactly like a var execpt
" it operates in a different window and useses
" current_watch for inspection

let s:WatchResult = copy(s:Var)

function! s:WatchResult.new(attrs)
  let new_watch = copy(s:Var.new(a:attrs))
  let new_watch.current = "current_watch"
  let new_watch.window = s:watches_window
  return new_watch
endfunction

" *** Watch classes (end)
