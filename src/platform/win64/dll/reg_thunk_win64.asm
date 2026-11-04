; Common thunk of the register-context call-site hooks (src/core/reg_hook.h), Windows x64.
; Entered by `jmp` from a per-site stub with r11 = the site record; [rsp] = the engine's return address.
; Pushes the general-purpose registers as an iex::RegContext, calls iex_reg_dispatch(ctx, record), pops them back
; (with the handler's changes) and returns to the engine.
EXTERN iex_reg_dispatch:PROC

.code
iex_reg_thunk PROC PUBLIC
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax
    ; rsp was 8 mod 16 after the engine's call; 15 pushes make it 16-aligned.
    mov rcx, rsp
    mov rdx, r11
    sub rsp, 32
    call iex_reg_dispatch
    add rsp, 32
    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15
    ret
iex_reg_thunk ENDP
END
