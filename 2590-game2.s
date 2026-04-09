.syntax unified
.cpu cortex-m4
.fpu softvfp
.thumb

.global Main
.global SysTick_Handler
.global EXTI0_IRQHandler

#include "definitions.S"

@ extra register/bit definitions 
.equ GPIOA_BASE,                  0x48000000
.equ RCC_APB2ENR,                 (RCC_BASE + 0x18)

.equ RCC_AHBENR_GPIOAEN_BIT,      17
.equ RCC_APB2ENR_SYSCFGEN_BIT,    0

@ ------------------------------------------------------------------
@ Game constants
@ ------------------------------------------------------------------

@ too fast game
@ .equ INITIAL_REACTION_TIME,       1200
@ .equ REACTION_DECREMENT,          300
@ .equ MIN_REACTION_TIME,           100
@ .equ MAX_LEVEL,                   4

@ .equ STATE_REACTION,              1
@ .equ STATE_DELAY,                 2
@ .equ STATE_FLASH_FAIL,            3
@ .equ STATE_FLASH_SUCCESS,         4

@ .equ FLASH_PERIOD_MS,             50
@ .equ FLASH_TOGGLES_FAIL,          4
@ .equ FLASH_TOGGLES_SUCCESS,       6

@ .equ MIN_INTERROUND_DELAY,        50
@ .equ RANDOM_DELAY_MASK,           0x007F

@ slow game
.equ INITIAL_REACTION_TIME,       2500
.equ REACTION_DECREMENT,          800
.equ MIN_REACTION_TIME,           400
.equ MAX_LEVEL,                   4

.equ STATE_REACTION,              1
.equ STATE_DELAY,                 2
.equ STATE_FLASH_FAIL,            3
.equ STATE_FLASH_SUCCESS,         4

.equ FLASH_PERIOD_MS,             100
.equ FLASH_TOGGLES_FAIL,          6
.equ FLASH_TOGGLES_SUCCESS,       8

.equ MIN_INTERROUND_DELAY,        200
.equ RANDOM_DELAY_MASK,           0x01FF

@ fast game
@ .equ INITIAL_REACTION_TIME,       1000
@ .equ REACTION_DECREMENT,          200
@ .equ MIN_REACTION_TIME,           150
@ .equ MAX_LEVEL,                   4

@ .equ STATE_REACTION,              1
@ .equ STATE_DELAY,                 2
@ .equ STATE_FLASH_FAIL,            3
@ .equ STATE_FLASH_SUCCESS,         4

@ .equ FLASH_PERIOD_MS,             40
@ .equ FLASH_TOGGLES_FAIL,          3
@ .equ FLASH_TOGGLES_SUCCESS,       4

@ .equ MIN_INTERROUND_DELAY,        40
@ .equ RANDOM_DELAY_MASK,           0x003F

@ ------------------------------------------------------------------
@ LED masks
@ ------------------------------------------------------------------
.equ LEVEL0_MASK,                 (1 << LD3_PIN)
.equ LEVEL1_MASK,                 (1 << LD7_PIN)
.equ LEVEL2_MASK,                 (1 << LD10_PIN)
.equ LEVEL3_MASK,                 (1 << LD6_PIN)

.equ FAIL_LED_MASK,               ((1 << LD5_PIN) | (1 << LD9_PIN) | (1 << LD8_PIN) | (1 << LD4_PIN))
.equ SUCCESS_LED_MASK,            ((1 << LD3_PIN) | (1 << LD7_PIN) | (1 << LD10_PIN) | (1 << LD6_PIN) | (1 << LD5_PIN) | (1 << LD9_PIN) | (1 << LD8_PIN) | (1 << LD4_PIN))
.equ ALL_LED_MASK,                SUCCESS_LED_MASK

@ Persistent game data
@ round number, time for valid press, timer decremented by Systick
@ current mode of game, remaining flash transitions, whether LEDs are lit
.section .data
current_level:    .word 0
reaction_time:    .word INITIAL_REACTION_TIME
countdown:        .word INITIAL_REACTION_TIME
game_state:       .word STATE_REACTION
flash_steps:      .word 0
flash_on:         .word 0

.section .text
.type Main, %function
Main:
    PUSH    {R4-R7, LR}


    @ Enable clocks:
    @   GPIOE for LEDs
    @   GPIOA for USER button pin
    @   SYSCFG for EXTI mapping

    LDR     R4, =RCC_AHBENR
    LDR     R5, [R4]
    ORR     R5, R5, #(1 << RCC_AHBENR_GPIOEEN_BIT)
    ORR     R5, R5, #(1 << RCC_AHBENR_GPIOAEN_BIT)
    STR     R5, [R4]

    LDR     R4, =RCC_APB2ENR
    LDR     R5, [R4]
    ORR     R5, R5, #(1 << RCC_APB2ENR_SYSCFGEN_BIT)
    STR     R5, [R4]

    @ Configure PE8..PE15 as outputs in one go
    LDR     R4, =GPIOE_MODER
    LDR     R5, [R4]
    LDR     R6, =0xFFFF0000
    BIC     R5, R5, R6
    LDR     R6, =0x55550000
    ORR     R5, R5, R6
    STR     R5, [R4]

    @ Configure EXTI0 for USER button on PA0
    @ user button handles presses
    LDR     R4, =SYSCFG_EXTIICR1
    LDR     R5, [R4]
    BIC     R5, R5, #0b1111          @ PA0 -> EXTI0
    STR     R5, [R4]

    LDR     R4, =EXTI_IMR
    LDR     R5, [R4]
    ORR     R5, R5, #1               @ unmask EXTI0
    STR     R5, [R4]

    LDR     R4, =EXTI_RTSR
    LDR     R5, [R4]
    BIC     R5, R5, #1               @ no rising-edge trigger
    STR     R5, [R4]

    LDR     R4, =EXTI_FTSR
    LDR     R5, [R4]
    ORR     R5, R5, #1               @ falling-edge trigger
    STR     R5, [R4]

    LDR     R4, =EXTI_PR
    MOV     R5, #1
    STR     R5, [R4]                 @ clear any EXTI0 pending flag

    LDR     R4, =NVIC_ISER
    MOV     R5, #(1 << 6)            @ EXTI0 IRQ channel
    STR     R5, [R4]

    @ Initialise game state
    BL      InitGame

    @ Configure SysTick for 1ms interrupt (8 MHz clock)
    @ acts as the game clock
    LDR     R4, =SCB_ICSR
    LDR     R5, =SCB_ICSR_PENDSTCLR
    STR     R5, [R4]

    LDR     R4, =SYSTICK_CSR
    MOV     R5, #0
    STR     R5, [R4]

    LDR     R4, =SYSTICK_LOAD
    LDR     R5, =7999
    STR     R5, [R4]

    LDR     R4, =SYSTICK_VAL
    MOV     R5, #1
    STR     R5, [R4]

    LDR     R4, =SYSTICK_CSR
    MOV     R5, #7                   @ ENABLE | TICKINT | CLKSOURCE
    STR     R5, [R4]

Idle_Loop:
    B       Idle_Loop


@ SysTick handler
@ configured to fire every 1ms
.type SysTick_Handler, %function
SysTick_Handler:
    PUSH    {R4-R7, LR}

    LDR     R4, =countdown
    LDR     R5, [R4]
    CMP     R5, #0
    BEQ     SysTick_AckAndReturn

    SUBS    R5, R5, #1
    STR     R5, [R4]
    BNE     SysTick_AckAndReturn

    @ countdown has just reached 0 -> react 
    LDR     R4, =game_state
    LDR     R5, [R4]

    @ if state reaction, timer expired during reaction phase, so player failed
    CMP     R5, #STATE_REACTION
    BEQ     SysTick_ReactionExpired

    @ if state is state delay, delay between rounds ended, so next round starts
    CMP     R5, #STATE_DELAY
    BEQ     SysTick_StartNextRound

    @ if flash fail/success, toggles flashing LEDS and either continues flash or resets game
    CMP     R5, #STATE_FLASH_FAIL
    BEQ     SysTick_AdvanceFlash

    CMP     R5, #STATE_FLASH_SUCCESS
    BEQ     SysTick_AdvanceFlash

@ clear pending SysTick and return block
    B       SysTick_AckAndReturn

SysTick_ReactionExpired:
    BL      StartFailureFlash
    B       SysTick_AckAndReturn

SysTick_StartNextRound:
    BL      ActivateCurrentLevel
    B       SysTick_AckAndReturn

SysTick_AdvanceFlash:
    BL      AdvanceFlash
    B       SysTick_AckAndReturn

@ reconfiguring SysTick
SysTick_AckAndReturn:
    LDR     R4, =SCB_ICSR
    LDR     R5, =SCB_ICSR_PENDSTCLR
    STR     R5, [R4]
    POP     {R4-R7, PC}


@ runs when user interrupt fires
.type EXTI0_IRQHandler, %function
EXTI0_IRQHandler:
    PUSH    {R4-R7, LR}

    @ clear EXTI0 pending flag immediately
    LDR     R4, =EXTI_PR
    MOV     R5, #1
    STR     R5, [R4]

    LDR     R4, =game_state
    LDR     R5, [R4]

    @ valid press only during active reaction state
    CMP     R5, #STATE_REACTION
    BEQ     EXTI_ValidPress

    @ fail if pressed during transition/delay between lights
    CMP     R5, #STATE_DELAY
    BEQ     EXTI_FailPress

    @ ignore presses during flash/reset states
    B       EXTI_Return

EXTI_ValidPress:
    BL      HandleReactionSuccess
    B       EXTI_Return

EXTI_FailPress:
    BL      StartFailureFlash

EXTI_Return:
    POP     {R4-R7, PC}


@ Game logic helpers
@ reset all variables to initial values
@ start in reaction state on level 0
@ turn on first level LED
.type InitGame, %function
InitGame:
    PUSH    {R4-R7, LR}

    BL      TurnOffAllLeds

    LDR     R4, =current_level
    MOV     R5, #0
    STR     R5, [R4]

    LDR     R4, =reaction_time
    LDR     R5, =INITIAL_REACTION_TIME
    STR     R5, [R4]

    LDR     R4, =countdown
    LDR     R5, =INITIAL_REACTION_TIME
    STR     R5, [R4]

    LDR     R4, =game_state
    MOV     R5, #STATE_REACTION
    STR     R5, [R4]

    LDR     R4, =flash_steps
    MOV     R5, #0
    STR     R5, [R4]

    LDR     R4, =flash_on
    MOV     R5, #0
    STR     R5, [R4]

    LDR     R0, =LEVEL0_MASK
    BL      SetLedMask

    POP     {R4-R7, PC}


@ runs when player presses button at correct time
@ turn off LEDs, advance level, reduce reation time
@ start a random delay before the next round
@ switch game_state to STATE_DELAY
.type HandleReactionSuccess, %function
HandleReactionSuccess:
    PUSH    {R4-R7, LR}

    @ turn off current round LEDs
    BL      TurnOffAllLeds

    @ current_level = current_level + 1
    LDR     R4, =current_level
    LDR     R5, [R4]
    ADDS    R5, R5, #1
    STR     R5, [R4]

    @ if current_level >= MAX_LEVEL -> full success
    CMP     R5, #MAX_LEVEL
    BGE     HandleReactionSuccess_FullSuccess

    @ reaction_time = max(reaction_time - REACTION_DECREMENT, MIN_REACTION_TIME)
    LDR     R4, =reaction_time
    LDR     R0, [R4]
    LDR     R1, =REACTION_DECREMENT
    SUB     R0, R0, R1
    LDR     R1, =MIN_REACTION_TIME
    CMP     R0, R1
    BGE     HandleReactionSuccess_StoreRT
    MOV     R0, R1

HandleReactionSuccess_StoreRT:
    STR     R0, [R4]

    @ countdown = semi random inter-round delay before next round
    LDR     R4, =SYSTICK_VAL
    LDR     R0, [R4]
    LDR     R1, =RANDOM_DELAY_MASK
    AND     R0, R0, R1
    LDR     R1, =MIN_INTERROUND_DELAY
    ADD     R0, R0, R1

    LDR     R4, =countdown
    STR     R0, [R4]

    LDR     R4, =game_state
    MOV     R5, #STATE_DELAY
    STR     R5, [R4]

    POP     {R4-R7, PC}

HandleReactionSuccess_FullSuccess:
    BL      StartSuccessFlash
    POP     {R4-R7, PC}


@ start current level
@ light LED for current level
@ load countdown with reaction_time
@ switch back to STATE_REACTION
.type ActivateCurrentLevel, %function
ActivateCurrentLevel:
    PUSH    {R4-R7, LR}

    BL      TurnOffAllLeds

    LDR     R4, =current_level
    LDR     R5, [R4]

    CMP     R5, #0
    BEQ     Activate_Level0
    CMP     R5, #1
    BEQ     Activate_Level1
    CMP     R5, #2
    BEQ     Activate_Level2
    CMP     R5, #3
    BEQ     Activate_Level3

    @ if somehow out of range, restart game
    BL      InitGame
    POP     {R4-R7, PC}

Activate_Level0:
    LDR     R0, =LEVEL0_MASK
    B       Activate_LevelMaskReady

Activate_Level1:
    LDR     R0, =LEVEL1_MASK
    B       Activate_LevelMaskReady

Activate_Level2:
    LDR     R0, =LEVEL2_MASK
    B       Activate_LevelMaskReady

Activate_Level3:
    LDR     R0, =LEVEL3_MASK

Activate_LevelMaskReady:
    BL      SetLedMask

    LDR     R4, =reaction_time
    LDR     R5, [R4]
    LDR     R4, =countdown
    STR     R5, [R4]

    LDR     R4, =game_state
    MOV     R5, #STATE_REACTION
    STR     R5, [R4]

    POP     {R4-R7, PC}


@ enter failure flash state
@ prepare flash counters & turn on failure LEDs
@ SysTick will handle the remaining flash toggles
.type StartFailureFlash, %function
StartFailureFlash:
    PUSH    {R4-R7, LR}

    BL      TurnOffAllLeds

    LDR     R4, =game_state
    MOV     R5, #STATE_FLASH_FAIL
    STR     R5, [R4]

    LDR     R4, =flash_steps
    MOV     R5, #FLASH_TOGGLES_FAIL
    STR     R5, [R4]

    LDR     R4, =flash_on
    MOV     R5, #1
    STR     R5, [R4]

    LDR     R4, =countdown
    MOV     R5, #FLASH_PERIOD_MS
    STR     R5, [R4]

    LDR     R0, =FAIL_LED_MASK
    BL      SetLedMask

    POP     {R4-R7, PC}

@ enter success flash state
@ prepare flash counters and turn on all LEDs
@ SysTick manages success flashing sequence
.type StartSuccessFlash, %function
StartSuccessFlash:
    PUSH    {R4-R7, LR}

    BL      TurnOffAllLeds

    LDR     R4, =game_state
    MOV     R5, #STATE_FLASH_SUCCESS
    STR     R5, [R4]

    LDR     R4, =flash_steps
    MOV     R5, #FLASH_TOGGLES_SUCCESS
    STR     R5, [R4]

    LDR     R4, =flash_on
    MOV     R5, #1
    STR     R5, [R4]

    LDR     R4, =countdown
    MOV     R5, #FLASH_PERIOD_MS
    STR     R5, [R4]

    LDR     R0, =SUCCESS_LED_MASK
    BL      SetLedMask

    POP     {R4-R7, PC}


@ toggle flash LEDs on/off
@ decrement remaining flash steps
@ if flashing finished, restart game
@ otherwise reload for next flash transition
.type AdvanceFlash, %function
AdvanceFlash:
    PUSH    {R4-R7, LR}

    @ determine mask from state
    LDR     R4, =game_state
    LDR     R5, [R4]
    CMP     R5, #STATE_FLASH_FAIL
    BEQ     AdvanceFlash_UseFailMask
    LDR     R0, =SUCCESS_LED_MASK
    B       AdvanceFlash_MaskReady

AdvanceFlash_UseFailMask:
    LDR     R0, =FAIL_LED_MASK

AdvanceFlash_MaskReady:
    @ toggle LEDs based on flash_on
    LDR     R4, =flash_on
    LDR     R5, [R4]
    CMP     R5, #0
    BEQ     AdvanceFlash_TurnOn

AdvanceFlash_TurnOff:
    BL      ClearLedMask
    MOV     R5, #0
    STR     R5, [R4]
    B       AdvanceFlash_AfterToggle

AdvanceFlash_TurnOn:
    BL      SetLedMask
    MOV     R5, #1
    STR     R5, [R4]

AdvanceFlash_AfterToggle:
    @ flash_steps--
    LDR     R4, =flash_steps
    LDR     R5, [R4]
    SUBS    R5, R5, #1
    STR     R5, [R4]
    BEQ     AdvanceFlash_Finished

    @ reload countdown for next flash phase
    LDR     R4, =countdown
    MOV     R5, #FLASH_PERIOD_MS
    STR     R5, [R4]

    POP     {R4-R7, PC}

AdvanceFlash_Finished:
    BL      InitGame
    POP     {R4-R7, PC}



@ LED helpers using GPIOE_BSRR

@ turn on LEDs specified by mask in R0
.type SetLedMask, %function
SetLedMask:
    PUSH    {R4, LR}
    LDR     R4, =GPIOE_BSRR
    STR     R0, [R4]
    POP     {R4, PC}

@ turn off LEDs specified by mask in R0
.type ClearLedMask, %function
ClearLedMask:
    PUSH    {R4, R1, LR}
    LDR     R4, =GPIOE_BSRR
    LSL     R1, R0, #16
    STR     R1, [R4]
    POP     {R4, R1, PC}


@ turn off every game LED on GPIOE
.type TurnOffAllLeds, %function
TurnOffAllLeds:
    PUSH    {LR}
    LDR     R0, =ALL_LED_MASK
    BL      ClearLedMask
    POP     {PC}

.end


