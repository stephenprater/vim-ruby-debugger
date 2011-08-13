" *** WindowWatch class (start)
" This is basically exactly like the variables window except it issue and
" eval every time for the watch varaibles

let s:WindowWatches = copy(s:Window)

function! s:WindowWatches.render() dict
  let watches = self.title . "\n"
  let watch_queue = g:RubyDebugger.watch_queue.queue
  for watch in watch_queue 
    let watches .= watch.render()
  endfor
  return watches
endfunction

function! s:window_watches_delete_node()
  let watch = s:WatchExpression.find_watch(s:WatchExpression.get_selected_expression())
  if watch != {} 
    call watch.delete()
    call s:watches_window.open()
  endif
endfunction

function! s:window_watches_eval_node()
  echo "not implemented yet"
endfunction

function! s:window_watches_activate_node()
  let watch = s:WatchExpression.get_selected()
  if watch != {} && watch.type == "VarParent"
    if watch.is_open
      call watch.close()
    else
      call watch.open()
    endif
  endif
  call g:RubyDebugger.queue.execute()
endfunction

function! s:WindowWatches.bind_mappings()
  nnoremap <buffer> <2-leftmouse> :call <SID>window_watches_activate_node()<cr>
  nnoremap <buffer> o :call <SID>window_watches_activate_node()<cr>
  nnoremap <buffer> d :call <SID>window_watches_delete_node()<cr>
  nnoremap <buffer> e :call <SID>window_watches_eval_node()<cr>
endfunction

function! s:WindowWatches.setup_syntax_highlighting()
    execute "syn match rdebugTitle #" . self.title . "#"

    syn match rdebugWatchId "^\d\+\s=>" 
    
    syn match rdebugPart #[| `]\+#
    syn match rdebugPartFile #[| `]\+-# contains=rdebugPart nextgroup=rdebugChild contained
    syn match rdebugChild #.\{-}\t# nextgroup=rdebugType contained

    syn match rdebugClosable #[| `]\+\~# contains=rdebugPart nextgroup=rdebugParent contained
    syn match rdebugOpenable #[| `]\++# contains=rdebugPart nextgroup=rdebugParent contained
    syn match rdebugParent #.\{-}\t# nextgroup=rdebugType contained

    syn match rdebugType #.\{-}\t# nextgroup=rdebugValue contained
    syn match rdebugValue #.*\t#he=e-1 nextgroup=rdebugId contained
    syn match rdebugId #.*# contained
    
    syn match rdebugParentLine '[| `]\+[+\~].*' contains=rdebugClosable,rdebugOpenable transparent
    syn match rdebugChildLine '[| `]\+-.*' contains=rdebugPartFile transparent

    hi def link rdebugWatchId Number
    hi def link rdebugTitle Identifier
    hi def link rdebugClosable Type
    hi def link rdebugOpenable Title
    hi def link rdebugPart Special
    hi def link rdebugPartFile Type
    hi def link rdebugChild Normal
    hi def link rdebugParent Directory
    hi def link rdebugType Type
    hi def link rdebugValue Special
    hi def link rdebugId Ignore
endfunction

" *** WindowWatches class (end)

