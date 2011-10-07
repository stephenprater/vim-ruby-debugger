" *** RubyDebugger Commands (what debugger returns)


" <breakpoint file="test.rb" line="1" threadId="1" />
" <suspended file='test.rb' line='1' threadId='1' />
" Jump to file/line where execution was suspended, set current line sign and get local variables
function! RubyDebugger.commands.jump_to_breakpoint(cmd) dict
  let attrs = s:get_tag_attributes(a:cmd) 
  call s:jump_to_file(s:rewrite_filename(attrs.file,'l'), attrs.line)
  call s:log("Jumped to breakpoint " . attrs.file . ":" . attrs.line)
  if has("signs")
    exe ":sign place " . s:current_line_sign_id . " line=" . attrs.line . " name=current_line file=" . s:rewrite_filename(attrs.file,'l')
  endif
endfunction


" <exception file="test.rb" line="1" type="NameError" message="some exception message" threadId="4" />
" Show message error and jump to given file/line
function! RubyDebugger.commands.handle_exception(cmd) dict
  let message_match = matchlist(a:cmd, 'message="\(.\{-}\)"')
  call g:RubyDebugger.commands.jump_to_breakpoint(a:cmd)
  echo "Exception message: " . s:unescape_html(message_match[1])
endfunction


" <catchpointSet exception="NoMethodError"/>
" Confirm setting of exception catcher
function! RubyDebugger.commands.set_exception(cmd) dict
  let attrs = s:get_tag_attributes(a:cmd)
  call s:log("Exception successfully set: " . attrs.exception)
endfunction


" <breakpointAdded no="1" location="test.rb:2" />
" Add debugger info to breakpoints (pid of debugger, debugger breakpoint's id)
" Assign rest breakpoints to debugger recursively, if there are breakpoints
" from old server runnings or not assigned breakpoints (e.g., if you at first
" set some breakpoints, and then run the debugger by :Rdebugger)
function! RubyDebugger.commands.set_breakpoint(cmd)
  call s:log("Received the breakpoint message, will add PID and number of breakpoint to the Breakpoint object")
  let attrs = s:get_tag_attributes(a:cmd)
  let file_match = matchlist(attrs.location, '\(.*\):\(.*\)')
  let file_match[1] = s:rewrite_filename(file_match[1],'l') 
  let pid = g:RubyDebugger.server.rdebug_pid

  " Find added breakpoint in array and assign debugger's info to it
  for breakpoint in g:RubyDebugger.breakpoints
    if expand(breakpoint.file) == expand(file_match[1]) && expand(breakpoint.line) == expand(file_match[2])
      call s:log("Found the Breakpoint object for " . breakpoint.file . ":" . breakpoint.line)
      let breakpoint.debugger_id = attrs.no
      let breakpoint.rdebug_pid = pid
      call s:log("Added id: " . breakpoint.debugger_id . ", PID:" . breakpoint.rdebug_pid . " to Breakpoint")
      if has_key(breakpoint, 'condition')
        call breakpoint.add_condition(breakpoint.condition)
      endif
    endif
  endfor

  call s:log("Breakpoint is set: " . file_match[1] . ":" . file_match[2])
  call g:RubyDebugger.queue.execute()
endfunction

function! RubyDebugger.commands.execute_watches(fill) dict
  if !g:RubyDebugger.watch_queue.is_empty()
    if a:fill
      call s:log("Filling watch working queue with " . len(g:RubyDebugger.watch_queue.queue) . " watches")
      let g:RubyDebugger.working_watch_queue = s:Queue.new()
      let g:RubyDebugger.working_watch_queue.queue = copy(g:RubyDebugger.watch_queue.queue)
    endif
    if !g:RubyDebugger.working_watch_queue.is_empty()
      let watch = g:RubyDebugger.working_watch_queue.unshift()
      call s:log("Executing watch " . watch.id . " => ". watch.expr)
      call g:RubyDebugger.queue.add('var inspect ' . watch.expr)
      let g:RubyDebugger.watch_pending = watch
      call g:RubyDebugger.queue.execute()
    endif
  endif
endfunction

function! RubyDebugger.commands.display_watch_result(tags) dict
  call s:log("Displaying watch result")
  let list_of_results = [] 

  for tag in a:tags
    let attrs = s:get_tag_attributes(tag)
    let result = s:WatchResult.new(attrs)
    call add(list_of_results, result)
  endfor

  if has_key(g:RubyDebugger, 'watch_pending') 
    let watch = g:RubyDebugger.watch_pending
    call s:log("Got initial inspection result for watch " . watch.id . " = " . string(list_of_results[0]))
    let watch.result = list_of_results[0]
    let watch.result.attributes.name = watch.expr
    if s:watches_window.is_open()
      call s:watches_window.open()
    endif
    unlet g:RubyDebugger.watch_pending
    call g:RubyDebugger.commands.execute_watches(0)
  else
    call s:log("Inspecting in current watch")
    let watch = g:RubyDebugger.current_watch
    if watch != {}
      call watch.add_childs(list_of_results)
      call s:log("Got results for further inspection of " . watch.attributes.objectId)
      call s:watches_window.open()
    else
      call s:log("Attempted to inspect an unknown variable")
    endif
    unlet g:RubyDebugger.current_watch
  endif
endfunction

" <variables>
"   <variable name="array" kind="local" value="Array (2 element(s))" type="Array" hasChildren="true" objectId="-0x2418a904"/>
" </variables>
" Assign list of got variables to parent variable and (optionally) show them
function! RubyDebugger.commands.set_variables(cmd)
  call s:log("Recieved variables command with " . a:cmd)
  let tags = s:get_tags(a:cmd)
  let list_of_variables = []
  
  if has_key(g:RubyDebugger, 'current_watch') || has_key(g:RubyDebugger, 'watch_pending')
    call g:RubyDebugger.commands.display_watch_result(tags)
    call s:log("returned from watch interrupt")
    return 0
  endif

  " Create hash from list of tags
  for tag in tags
    let attrs = s:get_tag_attributes(tag)
    let variable = s:Var.new(attrs)
    call add(list_of_variables, variable)
  endfor

  " If there is no variables, create unnamed root variable. Local variables
  " will be chilren of this variable
  if g:RubyDebugger.variables == {}
    let g:RubyDebugger.variables = s:VarParent.new({'hasChildren': 'true'})
    let g:RubyDebugger.variables.is_open = 1
    let g:RubyDebugger.variables.children = []
  endif

  " If g:RubyDebugger.current_variable exists, then it contains parent
  " variable of got subvariables. Assign them to it.
  if has_key(g:RubyDebugger, 'current_variable')
    let variable = g:RubyDebugger.current_variable
    if variable != {}
      call variable.add_childs(list_of_variables)
      call s:log("Opening child variable: " . variable.attributes.objectId)
      " Variables Window is always open if we got subvariables
      call s:variables_window.open()
    else
      call s:log("Can't found variable")
    endif
    unlet g:RubyDebugger.current_variable
  else
    " Otherwise, assign them to unnamed root variable
    if g:RubyDebugger.variables.children == []
      call g:RubyDebugger.variables.add_childs(list_of_variables)
      call s:log("Initializing local variables")
      if s:variables_window.is_open()
        " show variables only if Variables Window is open
        call s:variables_window.open()
      endif
    endif
  endif

endfunction


" <eval expression="User.all" value="[#User ... ]" />
" Just show result of evaluation
function! RubyDebugger.commands.eval(cmd)
  " rdebug-ide-gem doesn't escape attributes of tag properly, so we should not
  " use usual attribute extractor here...
  let match = matchlist(a:cmd, "<eval expression=\"\\(.\\{-}\\)\" value=\"\\(.*\\)\" \\/>")
  echo "Evaluated expression:\n" . s:unescape_html(match[1]) ."\nResulted value is:\n" . match[2] . "\n"
endfunction


" <processingException type="SyntaxError" message="some message" />
" Just show exception message
function! RubyDebugger.commands.processing_exception(cmd)
  let attrs = s:get_tag_attributes(a:cmd)
  if attrs.type == "NameError" && has_key(g:RubyDebugger,'watch_pending')
    call s:log("Recieved NameError during pending watch operation for watch " . g:RubyDebugger.watch_pending)
    let watch = s:WatchExpression.find_watch(g:RubyDebugger.watch_pending)
    let watch.result = "undefined (out of scope?)"
    unlet g:RubyDebugger.watch_pending
    return
  endif
  let message = "RubyDebugger Exception, type: " . attrs.type . ", message: " . attrs.message
  echo message
  call s:log(message)
endfunction


" <frames>
"   <frame no='1' file='/path/to/file.rb' line='21' current='true' />
"   <frame no='2' file='/path/to/file.rb' line='11' />
" </frames>
" Assign all frames, fill Frames window by them
function! RubyDebugger.commands.trace(cmd)
  let tags = s:get_tags(a:cmd)
  let list_of_frames = []

  " Create hash from list of tags
  for tag in tags
    let attrs = s:get_tag_attributes(tag)
    let frame = s:Frame.new(attrs)
    call add(list_of_frames, frame)
  endfor

  let g:RubyDebugger.frames = list_of_frames

  if s:frames_window.is_open()
    " show backtrace only if Backtrace Window is open
    call s:frames_window.open()
  endif
endfunction


" <error>Error</error>
" Just show error
function! RubyDebugger.commands.error(cmd)
  let error_match = s:get_inner_tags(a:cmd) 
  if !empty(error_match)
    let error = error_match[1]
    if error =~ '/There is no thread suspended/'
      " find bad command
      let error_cmd = matchstr(error,"/'.*")
      let error_cmd = strpart(error_cmd,1,strlen(error_cmd)-1)
      if g:RubyDebugger.interrupt_queue.is_empty()
        call g:RubyDebugger.queue.add('interrupt')
        call g:RubyDebugger.queue.execute()
      endif
      g:RubyDebugger.interrupt_queue.add(error_add)
      echo "Couldn't execute : " . error_cmd . " so saving for later."
    else
      echo "RubyDebugger Error: " . error
      call s:log("Got error: " . error)
    endif
  endif
endfunction


" <message>Message</message>
" Just show message
function! RubyDebugger.commands.message(cmd)
  let message_match = s:get_inner_tags(a:cmd) 
  if !empty(message_match)
    let message = message_match[1]
    echo "RubyDebugger Message: " . message
    if message == "finished"
      call g:RubyDebugger.stop()
    endif
    call s:log("Got message: " . message)
  endif
endfunction

" *** End of debugger Commands 

