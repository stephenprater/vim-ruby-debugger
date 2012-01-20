" *** Public interface (start)

let RubyDebugger = { 
    \ 'commands': {}, 
    \ 'variables': {}, 
    \ 'settings': {},
    \ 'watch_results': [], 
    \ 'breakpoints': [], 
    \ 'frames': [], 
    \ 'exceptions': [],
    \ 'status': 'inactive'
  \}

let g:RubyDebugger.queue = s:Queue.new()

" this queue lets us give it things to do as soon as there's a thread to
" execute them in, particularly loading files
let g:RubyDebugger.interrupt_queue = s:Queue.new()

" this queue is for watches - we can only send one watch at a time
" to the server because the response is async.  however,
" the debugger itself is single threaded, so you can count
" on them coming back in the same order they left in
let g:RubyDebugger.watch_queue = s:Queue.new()


" Run debugger server. It takes one optional argument with path to debugged
" ruby script ('script/server webrick' by default)
function! RubyDebugger.start(...) dict
  call s:log("Executing :Rdebugger...")
  let g:RubyDebugger.server = s:Server.new(s:hostname, s:rdebug_port, s:relay_port, s:runtime_dir, s:tmp_file, s:server_output_file)
  let script_string = a:0 && !empty(a:1) ? a:1 : g:ruby_debugger_default_script
  echo "Loading debugger..."
  call g:RubyDebugger.server.start(s:get_escaped_absolute_path(script_string))

  let g:RubyDebugger.exceptions = []
  for breakpoint in g:RubyDebugger.breakpoints
    call g:RubyDebugger.queue.add(breakpoint.command())
  endfor
  call g:RubyDebugger.queue.add('start')
  echo "Debugger started"
  let g:RubyDebugger.status = 'local'
  call g:RubyDebugger.queue.execute()
  doauto User RdbActivate
endfunction

"Connect to a remote debugger
function! RubyDebugger.connect(...) dict
  if empty(a:1)
    echoerr "Need <server>:<port> <remote dir> <local dir>"
    return
  endif

  call s:log("Executing :Rdebugger Connect...")
  let server_params = split(a:1, ':')
  echo server_params
  let server_name = server_params[0]
  let server_port = server_params[1]

  let s:hostname = server_name
  let s:rdebug_port = server_port

  let g:RubyDebugger.remote = 1
  if len(a:000) > 1 
    let g:RubyDebugger.remote_directory = a:2
    let g:RubyDebugger.local_directory = a:3
  endif

  let g:RubyDebugger.server = s:Server.new_remote(s:hostname, s:rdebug_port, s:relay_port, s:runtime_dir, s:tmp_file, s:server_output_file)
  call g:RubyDebugger.server.connect()

  let g:RubyDebugger.exceptions = []
  for breakpoint in g:RubyDebugger.breakpoints
    " determine remote file for breakpoint set before our connection
    let breakpoint.remote_file = s:rewrite_filename(breakpoint.file,'r')
    call g:RubyDebugger.queue.add(breakpoint.command())
  endfor
  call g:RubyDebugger.queue.add('start')
  echo "Debugger connected!"
  let g:RubyDebugger.status = 'remote'
  call g:RubyDebugger.queue.execute()
  doauto User RdbActivate
endfunction

" Stop running server.
function! RubyDebugger.stop() dict
  if has_key(g:RubyDebugger, 'remote')
    let s:hostname = s:default_hostname
    let s:rdebug_port = s:default_rdebug_port
    unlet g:RubyDebugger.remote
  endif
  call g:RubyDebugger.server.stop()
  let g:RubyDebugger.status = 'inactive'
  doauto User RdbDeactivate
endfunction

"send interrupt to the server
function! RubyDebugger.interrupt() dict
  call s:log("Will send interrupt if program is running")
  if has_key(g:RubyDebugger,'remote') || has_key(g:RubyDebugger, 'server')  && g:RubyDebugger.server.is_running
    call g:RubyDebugger.queue.add('interrupt')
    call g:RubyDebugger.queue.execute()
  endif
endfunction

function! RubyDebugger.watch(expr) dict
  call s:log("Adding watch expression '" . a:expr . "'")
  let watch_expression = s:WatchExpression.new(a:expr)
  call g:RubyDebugger.watch_queue.add(watch_expression)
  call add(g:RubyDebugger.watch_results, watch_expression) 
  if s:watches_window.is_open()
    call s:watches_window.open()
    exe "wincmd p"
  endif
  call s:log("Executing watches")
  call g:RubyDebugger.commands.execute_watches(1)
endfunction

" This function receives commands from the debugger. When ruby_debugger.rb
" gets output from rdebug-ide, it writes it to the special file and 'kick'
" the plugin by remotely calling RubyDebugger.receive_command(), e.g.:
" vim --servername VIM --remote-send 'call RubyDebugger.receive_command()'
" That's why +clientserver is required
" This function analyzes the special file and gives handling to right command
function! RubyDebugger.receive_command() dict
  let file_contents = join(readfile(s:tmp_file), "")
  call s:log("Received command: " . file_contents)
  let commands = split(file_contents, s:separator)
  let watch_trigger = 0
  for cmd in commands
    if !empty(cmd)
      if match(cmd, '<breakpoint ') != -1
        call g:RubyDebugger.commands.jump_to_breakpoint(cmd)
        let watch_trigger = 1
      elseif match(cmd, '<suspended ') != -1
        call g:RubyDebugger.commands.jump_to_breakpoint(cmd)
        let watch_trigger = 1
      elseif match(cmd, '<exception ') != -1
        call g:RubyDebugger.commands.handle_exception(cmd)
        let watch_trigger = 1
      elseif match(cmd, '<breakpointAdded ') != -1
        call g:RubyDebugger.commands.set_breakpoint(cmd)
      elseif match(cmd, '<catchpointSet ') != -1
        call g:RubyDebugger.commands.set_exception(cmd)
      elseif match(cmd, '<variables>') != -1
        call g:RubyDebugger.commands.set_variables(cmd)
        call s:log("returning from variables")
      elseif match(cmd, '<error>') != -1
        call g:RubyDebugger.commands.error(cmd)
      elseif match(cmd, '<message>') != -1
        call g:RubyDebugger.commands.message(cmd)
      elseif match(cmd, '<eval ') != -1
        call g:RubyDebugger.commands.eval(cmd)
      elseif match(cmd, '<processingException ') != -1
        call g:RubyDebugger.commands.processing_exception(cmd)
      elseif match(cmd, '<frames>') != -1
        call g:RubyDebugger.commands.trace(cmd)
      endif
    endif
  endfor
  if watch_trigger && !g:RubyDebugger.watch_queue.is_empty()
    call s:log("Executing watches by filling from watch_queue")
    call g:RubyDebugger.commands.execute_watches(1)
  endif
  call g:RubyDebugger.queue.execute()
endfunction


function! RubyDebugger.send_command_wrapper(command)
  call g:RubyDebugger.send_command(a:command)
endfunction

" We set function this way, because we want have possibility to mock it by
" other function in tests
let RubyDebugger.send_command = function("<SID>send_message_to_debugger")

function! RubyDebugger.set_mappings() dict
  noremap <leader>s :RdbStep<CR>
  noremap <leader>f :RdbFinish<CR>
  noremap <leader>n :RdbNext<CR>
  noremap <leader>c :RdbContinue<CR>
  noremap <leader>e :RdbEval<Space>
endfunction

function! RubyDebugger.unset_mappings() dict
  nunmap <leader>s
  nunmap <leader>f
  nunmap <leader>n
  nunmap <leader>c
  nunmap <leader>e
endfunction

function! RubyDebugger.debugger_workspace(op) dict
  if (a:op == 'open')
    if !(s:variables_window.is_open())
      call s:variables_window.open()
    endif
    if !(s:frames_window.is_open())
      call s:frames_window.open()
    endif
    if !(s:breakpoints_window.is_open())
      call s:breakpoints_window.open()
    endif
    if !(s:watches_window.is_open())
      call s:watches_window.open()
    endif
  elseif (a:op == 'close')
    if s:variables_window.is_open()
      call s:variables_window.close()
    endif
    if s:frames_window.is_open()
      call s:frames_window.close()
    endif
    if s:breakpoints_window.is_open()
      call s:breakpoints_window.close()
    endif
    if !(s:watches_window.is_open())
      call s:watches_window.close()
    endif
  endif
endfunction


" Open variables window
function! RubyDebugger.open_variables() dict
  call s:variables_window.toggle()
  call s:log("Opened variables window")
  call g:RubyDebugger.queue.execute()
endfunction


" Open breakpoints window
function! RubyDebugger.open_breakpoints() dict
  call s:breakpoints_window.toggle()
  call s:log("Opened breakpoints window")
  call g:RubyDebugger.queue.execute()
endfunction

"Open Watches
function! RubyDebugger.open_watches() dict
  call s:watches_window.toggle()
  call s:log("Opened watches window")
  call g:RubyDebugger.queue.execute()
endfunction

" Open frames window
function! RubyDebugger.open_frames() dict
  call s:frames_window.toggle()
  call s:log("Opened frames window")
  call g:RubyDebugger.queue.execute()
endfunction

"Order the debugger to reload the file
function! RubyDebugger.reload_file(file) dict
  let remote_file = s:rewrite_filename(a:file,'r')
  call g:RubyDebugger.queue.add("load " . remote_file)
  call g:RubyDebugger.queue.execute()
endfunction

" Set/remove breakpoint at current position. If argument
" is given, it will set conditional breakpoint (argument is condition)
function! RubyDebugger.toggle_breakpoint(...) dict
  let line = line(".")
  let file = s:get_filename()
  " that's basically just for the log
  let remote_file = s:rewrite_filename(file,'r')
  call s:log("Trying to toggle a breakpoint in the file " . (remote_file ? remote_file : file) . ":" . line)
  let existed_breakpoints = filter(copy(g:RubyDebugger.breakpoints), 'v:val.line == ' . line . ' && v:val.file == "' . escape(file, '\') . '"')
  " If breakpoint with current file/line doesn't exist, create it. Otherwise -
  " remove it
  if empty(existed_breakpoints)
    call s:log("There is no already set breakpoint, so create new one")
    let breakpoint = s:Breakpoint.new(file, line)
    call add(g:RubyDebugger.breakpoints, breakpoint)
    call s:log("Added Breakpoint object to RubyDebugger.breakpoints array")
    call breakpoint.send_to_debugger() 
  else
    call s:log("There is already set breakpoint presented, so delete it")
    let breakpoint = existed_breakpoints[0]
    call filter(g:RubyDebugger.breakpoints, 'v:val.id != ' . breakpoint.id)
    call s:log("Removed Breakpoint object from RubyDebugger.breakpoints array")
    call breakpoint.delete()
  endif
  " Update info in Breakpoints window
  if s:breakpoints_window.is_open()
    call s:breakpoints_window.open()
    exe "wincmd p"
  endif
  call g:RubyDebugger.queue.execute()
endfunction


" Remove all breakpoints
function! RubyDebugger.remove_breakpoints() dict
  for breakpoint in g:RubyDebugger.breakpoints
    call breakpoint.delete()
  endfor
  let g:RubyDebugger.breakpoints = []
  call g:RubyDebugger.queue.execute()
endfunction


" Eval the passed in expression
function! RubyDebugger.eval(exp) dict
  let quoted = s:quotify(a:exp)
  call g:RubyDebugger.queue.add("eval " . quoted)
  call g:RubyDebugger.queue.execute()
endfunction


" Sets conditional breakpoint where cursor is placed
function! RubyDebugger.conditional_breakpoint(exp) dict
  let line = line(".")
  let file = s:get_filename()
  let existed_breakpoints = filter(copy(g:RubyDebugger.breakpoints), 'v:val.line == ' . line . ' && v:val.file == "' . escape(file, '\') . '"')
  " If breakpoint with current file/line doesn't exist, create it. Otherwise -
  " remove it
  if empty(existed_breakpoints)
    echo "You can set condition only to already set breakpoints. Move cursor to set breakpoint and add condition"
  else
    let breakpoint = existed_breakpoints[0]
    let quoted = s:quotify(a:exp)
    call breakpoint.add_condition(quoted)
    " Update info in Breakpoints window
    if s:breakpoints_window.is_open()
      call s:breakpoints_window.open()
      exe "wincmd p"
    endif
    call g:RubyDebugger.queue.execute()
  endif
endfunction


" Catch all exceptions with given name
function! RubyDebugger.catch_exception(exp) dict
  if has_key(g:RubyDebugger, 'server') && g:RubyDebugger.server.is_running()
    let quoted = s:quotify(a:exp)
    let exception = s:Exception.new(quoted)
    call add(g:RubyDebugger.exceptions, exception)
    if s:breakpoints_window.is_open()
      call s:breakpoints_window.open()
      exe "wincmd p"
    endif
    call g:RubyDebugger.queue.execute()
  else
    echo "Sorry, but you can set Exceptional Breakpoints only with running debugger"
  endif
endfunction


" Next
function! RubyDebugger.next() dict
  call g:RubyDebugger.queue.add("next")
  call s:clear_current_state()
  call s:log("Step over")
  call g:RubyDebugger.queue.execute()
endfunction


" Step
function! RubyDebugger.step() dict
  call g:RubyDebugger.queue.add("step")
  call s:clear_current_state()
  call s:log("Step into")
  call g:RubyDebugger.queue.execute()
endfunction


" Finish
function! RubyDebugger.finish() dict
  call g:RubyDebugger.queue.add("finish")
  call s:clear_current_state()
  call s:log("Step out")
  call g:RubyDebugger.queue.execute()
endfunction


" Continue
function! RubyDebugger.continue() dict
  call g:RubyDebugger.queue.add("cont")
  call s:clear_current_state()
  call s:log("Continue")
  call g:RubyDebugger.queue.execute()
endfunction


" Exit
function! RubyDebugger.exit() dict
  if has_key(g:RubyDebugger,'remote')
    if(!confirm("Quit remote program? (Use :RdbStop to disconnect without killing the remote)", "&Yes\n&No", 1))
      return 0
    endif
  endif
  call g:RubyDebugger.queue.add("exit")
  call s:clear_current_state()
  call g:RubyDebugger.queue.execute()
  call g:RubyDebugger.stop()
endfunction


" Show output log of Ruby script
function! RubyDebugger.show_log() dict
  exe "view " . s:server_output_file
  setlocal autoread
  " Per gorkunov's request 
  setlocal wrap
  setlocal nonumber
  if exists(":AnsiEsc")
    exec ":AnsiEsc"
  endif
endfunction


" Debug current opened test
function! RubyDebugger.run_test() dict
  let file = s:get_filename()
  if file =~ '_spec\.rb$'
    call g:RubyDebugger.start(g:ruby_debugger_spec_path . ' ' . file)
  elseif file =~ '\.feature$'
    call g:RubyDebugger.start(g:ruby_debugger_cucumber_path . ' ' . file)
  elseif file =~ '_test\.rb$'
    call g:RubyDebugger.start(file)
  endif
endfunction


" *** Public interface (end)



