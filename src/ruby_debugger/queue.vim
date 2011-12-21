" *** Queue class (start)

let s:Queue = {}

" ** Public methods

" Constructor of new queue.
function! s:Queue.new() dict
  let var = copy(self)
  let var.queue = []
  let var.after = ""
  return var
endfunction


" Execute next command in the queue and remove it from queue
function! s:Queue.execute() dict
  if !empty(self.queue)
    call s:log("Executing queue")
    let message = join(self.queue, s:separator)
    call self.empty()
    call g:RubyDebugger.send_command(message)
  endif
  call s:log("the queue was empty")  
endfunction


" Execute 'after' hook only if queue is empty
function! s:Queue.after_hook() dict
  if self.after != "" && empty(self.queue)
    call self.after()
  endif
endfunction

" remove the first item off the queue 
function! s:Queue.unshift() dict
  let element = remove(self.queue,0)
  call s:log("Popping " . string(element) . " off queue.")
  return element
endfunction

function! s:Queue.add(element) dict
  call s:log("Adding '" . string(a:element) . "' to queue")
  call add(self.queue, a:element)
endfunction


function! s:Queue.empty() dict
  let self.queue = []
endfunction

function! s:Queue.is_empty() dict
  if empty(self.queue)
    return 1
  else
    return 0
  endif
endfunction

" *** Queue class (end)
