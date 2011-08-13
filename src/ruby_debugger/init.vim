if exists("g:ruby_debugger_loaded")
  finish
endif

noremap <leader>db :RdbAddBreakpoint<CR>
noremap <leader>dd :RdbDeleteBreakpoint<CR>
noremap <leader>dv :RdbVariablesWindow<CR> 
noremap <leader>dm :RdbBreakpointsWindow<CR> 
noremap <leader>dt :RdbFramesWindow<CR>

augroup vim_ruby_debugger
  autocmd User RdbActivate call ruby_debugger#activate()
  autocmd User RdbDeactivate call ruby_debugger#deactivate()
augroup END

function! ruby_debugger#activate() 
  call g:RubyDebugger.debugger_workspace('open')
  call g:RubyDebugger.set_mappings()
  augroup RdbActivated
    autocmd!
    autocmd BufWritePost *.rb call g:RubyDebugger.reload_file(expand('<afile>:p'))
  augroup END
endfunction

function! ruby_debugger#deactivate() 
  call g:RubyDebugger.debugger_workspace('close')
  call g:RubyDebugger.unset_mappings()
  autocmd! RdbActivated
endfunction

command! -nargs=0 RdbAddBreakpoint call g:RubyDebugger.toggle_breakpoint()
command! -nargs=0 RdbDeleteBreakpoint call g:RubyDebugger.remove_breakpoints()
command! -nargs=0 RdbVariablesWindow call g:RubyDebugger.open_variables()
command! -nargs=0 RdbBreakpointsWindow call g:RubyDebugger.open_breakpoints()
command! -nargs=0 RdbFramesWindow call g:RubyDebugger.open_frames()
command! -nargs=0 RdbStep call g:RubyDebugger.step()
command! -nargs=0 RdbFinish call g:RubyDebugger.finish()
command! -nargs=0 RdbNext call g:RubyDebugger.next()
command! -nargs=0 RdbContinue call g:RubyDebugger.continue()
command! -nargs=0 RdbExit call g:RubyDebugger.exit()


command! -nargs=* -complete=file Rdebugger call ruby_debugger#load_debugger() | call g:RubyDebugger.start(<q-args>) 
command! -nargs=* -complete=file RdbConnect call ruby_debugger#load_debugger() | call g:RubyDebugger.connect(<f-args>)
command! -nargs=0 RdbInterrupt call g:RubyDebugger.interrupt()
command! -nargs=0 RdbQuit call g:RubyDebugger.exit()
command! -nargs=0 RdbStop call g:RubyDebugger.stop() 
command! -nargs=1 RdbCommand call g:RubyDebugger.send_command_wrapper(<q-args>) 
command! -nargs=0 RdbTest call g:RubyDebugger.run_test() 
command! -nargs=1 RdbEval call g:RubyDebugger.eval(<q-args>)
command! -nargs=1 RdbWatch call g:RubyDebugger.watch(<q-args>)
command! -nargs=1 RdbCond call g:RubyDebugger.conditional_breakpoint(<q-args>)
command! -nargs=1 RdbCatch call g:RubyDebugger.catch_exception(<q-args>)
command! -nargs=0 RdbLog call ruby_debugger#load_debugger() | call g:RubyDebugger.show_log()

let g:ruby_debugger_loaded = 1

