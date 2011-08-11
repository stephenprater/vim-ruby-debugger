" *** WindowWatch class (start)
" This is basically exactly like the variables window except it issue and
" eval every time for the watch varaibles

let s:WindowWatches = copy(s:Window)

function! s:WindowWatches.render() dict
  let watches = self.title . "\n"
  let watches .= (g:RubyDebugger.watches = {} ? '' : g:RubyDebugger.watches.render())
  return watches
endfunction

function! s:window_watches_activate_node()
  let variable = s:Var.get_selected()
  if variable != {} && variable.type == "VarParent"
    if variable.is_open
      call variable.close()
    else
      call variable.open()
    endif
  endif
  call g:RubyDebugger.queue.execute()
endfunction

function! s:WindowWatches.setup_syntax_highlighting()
    execute "syn match rdebugTitle #" . self.title . "#"

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

