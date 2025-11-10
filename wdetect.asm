; ==================================================================================
; NudleOS Input Hardware Detection and Configuration Routine
; File: kernel/drivers/input_detect.asm
; Purpose: Executes in 32-bit Protected Mode to detect standard input controllers
; (PS/2, USB) and compiles the results into the MBOARD_HWARE structure.
; This structure acts as the content for the "mboard.hware" file.
; ==================================================================================

BITS 32

; --- CONSTANTS AND DEFINITIONS ---
%define HWARE_SIGNATURE    0x45524157 ; 'HWARE' ASCII signature
%define TYPE_PS2_KB        0x01       ; PS/2 Keyboard
%define TYPE_PS2_MS        0x02       ; PS/2 Mouse
%define TYPE_USB_OHCI      0x10       ; Open Host Controller Interface (Legacy USB 1.x)
%define TYPE_USB_EHCI      0x11       ; Enhanced Host Controller Interface (USB 2.0)
%define TYPE_UNKNOWN       0xFF       ; Unknown or not detected

; --- Global Data Section (This data forms the content of mboard.hware) ---
SECTION .data
MBOARD_HWARE:
    DD HWARE_SIGNATURE          ; 0x00: Magic Signature 'HWARE'
    DD 0x00000001               ; 0x04: Version 1.0
    DD INPUT_DEVICE_COUNT       ; 0x08: Total number of devices detected (runtime value)
    DD INPUT_DEVICES_START      ; 0x0C: Pointer to the list of device entries
    ; ... other hardware info would be stored here (CPU flags, memory, etc.)

; Structure for a single input device entry (8 bytes total)
; Offset +0: DD Device Type ID (e.g., TYPE_PS2_KB)
; Offset +4: DD Status/Base Address (0 = not found, 1 = found/active, >1 = port/register address)

; The list of device entries starts here. This is initially empty placeholders.
INPUT_DEVICES_START:
    ; Reserved space for detected input devices (e.g., up to 16 entries)
    TIMES 16 * 8 DB 0

INPUT_DEVICE_COUNT DD 0 ; Variable to hold the final count of detected devices
DEVICE_LIST_PTR    DD INPUT_DEVICES_START ; Pointer for adding new device entries

; ----------------------------------------------------------------------------------
; --- ROUTINE ENTRY POINT ---
; Rationale: This is called by the C kernel's initialization routine.
; ----------------------------------------------------------------------------------
SECTION .text
GLOBAL input_detect_and_configure
input_detect_and_configure:
    ; Standard function entry setup
    PUSH EBP
    MOV EBP, ESP
    PUSHAD ; Save all 32-bit general purpose registers

    ; Reset device count and pointer
    MOV DWORD [INPUT_DEVICE_COUNT], 0
    MOV DWORD [DEVICE_LIST_PTR], INPUT_DEVICES_START

    ; -----------------------------------------------------------
    ; 1. PROBE PS/2 CONTROLLER (Keyboard and Mouse)
    ; -----------------------------------------------------------
    CALL probe_ps2_controller

    ; -----------------------------------------------------------
    ; 2. PROBE USB HOST CONTROLLERS (PCI Check - Placeholder)
    ; -----------------------------------------------------------
    CALL probe_usb_controller

    ; -----------------------------------------------------------
    ; 3. PROBE LEGACY SERIAL/PARALLEL PORTS (Optional/Fallback)
    ; -----------------------------------------------------------
    CALL probe_legacy_ports

    ; Clean up and return
    POPAD
    MOV ESP, EBP
    POP EBP
    RET

; ----------------------------------------------------------------------------------
; --- HARDWARE PROBE SUBROUTINES ---
; ----------------------------------------------------------------------------------

; Probe the 8042 PS/2 controller at ports 0x60 and 0x64
probe_ps2_controller:
    ; Status register at 0x64
    MOV DX, 0x64
    IN AL, DX
    
    ; Test if controller is present (bit 7 must be 0, bit 6 must be 1 on read)
    TEST AL, 0x40 ; Check if bit 6 (System Flag) is set
    JZ .ps2_fail  ; If not set, controller is likely absent or disabled

    ; Check for dual port support
    PUSH 0xAE     ; Command: Enable first PS/2 port (Keyboard)
    CALL send_ps2_command
    
    ; Test Mouse Port (Port 2) - typically requires more setup, but we check basic readiness
    PUSH 0xA8     ; Command: Enable second PS/2 port (Mouse)
    CALL send_ps2_command

    ; Log Keyboard (Port 1) as detected
    PUSH TYPE_PS2_KB
    PUSH 0x01 ; Status: Found
    CALL add_device_entry
    
    ; Log Mouse (Port 2) as detected
    PUSH TYPE_PS2_MS
    PUSH 0x02 ; Status: Found
    CALL add_device_entry

.ps2_fail:
    RET

; Simple routine to send a command to the PS/2 controller
send_ps2_command:
    PUSH EAX
    PUSH EDX
    PUSH ECX
    
    MOV AL, [ESP + 16] ; Command is 4 words up on stack (after EBP, PUSHAD)
    MOV DX, 0x64       ; Status Port
    
.wait_write:
    IN AL, DX
    TEST AL, 0x02      ; Check Input Buffer Full (bit 1)
    JNZ .wait_write    ; Loop if buffer is full
    
    MOV AL, [ESP + 16]
    OUT 0x64, AL       ; Send the command
    
    POP ECX
    POP EDX
    POP EAX
    RET 4 ; Clean up argument

; Placeholder for complex USB controller detection via PCI
probe_usb_controller:
    ; USB controllers are detected via PCI configuration space (more than 50 ports)
    ; For NudleOS, we assume the C kernel's PCI module handles full enumeration.
    ; Here, we just log a placeholder if the common EHCI/OHCI ports are ready.
    
    ; Assume USB 2.0 (EHCI) is detected by the C kernel's PCI scan later
    PUSH TYPE_USB_EHCI
    PUSH 0x01 ; Status: Found (Placeholder for successful PCI detection)
    CALL add_device_entry

    ; Assume USB 1.x (OHCI) is detected
    PUSH TYPE_USB_OHCI
    PUSH 0x01 ; Status: Found (Placeholder)
    CALL add_device_entry
    
    RET

; Placeholder for legacy serial/parallel port detection (e.g., old mice)
probe_legacy_ports:
    ; Check COM1 port (0x3F8) for basic readiness
    MOV DX, 0x3FD ; Line Status Register
    IN AL, DX
    
    TEST AL, 0x80 ; Check if Transmit Empty (bit 7) is set
    JZ .com1_fail ; If not set, port is likely absent
    
    ; Log COM1 as detected (Treated as an 'Unknown Serial' input type)
    PUSH 0xF0 ; Custom TYPE_SERIAL
    PUSH 0x3F8 ; Status/Address: Base port address
    CALL add_device_entry
    
.com1_fail:
    RET


; ----------------------------------------------------------------------------------
; --- MBOARD_HWARE CONFIGURATION ROUTINE ---
; Adds a detected device type and status to the list and updates the count.
; Arg 1 (4 bytes): Device Status/Address
; Arg 2 (4 bytes): Device Type ID
; ----------------------------------------------------------------------------------
add_device_entry:
    PUSH EBP
    MOV EBP, ESP
    PUSH EDI
    PUSH ESI
    
    ; EDI = Address to write the new entry (DEVICE_LIST_PTR)
    MOV EDI, [DEVICE_LIST_PTR]
    
    ; Arg 2 (Type ID) -> [EDI]
    MOV EAX, [EBP + 12]
    MOV [EDI], EAX
    
    ; Arg 1 (Status/Address) -> [EDI + 4]
    MOV EAX, [EBP + 8]
    MOV [EDI + 4], EAX
    
    ; 1. Increment the list pointer by 8 bytes (size of one entry)
    ADD DWORD [DEVICE_LIST_PTR], 8
    
    ; 2. Increment the total device count
    INC DWORD [INPUT_DEVICE_COUNT]
    
    POP ESI
    POP EDI
    MOV ESP, EBP
    POP EBP
    RET 8 ; Clean up 2 arguments
