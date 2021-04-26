;Prototypes
SetBoidData PROTO C
UpdateBoidData PROTO C
PrintBoid PROTO C
Atan2 PROTO C

;Macros

; num0, num1, t
; xmm0, xmm1, xmm2
_lerpFloat macro num0, num1, t
	movss xmm0, num0
	movss xmm1, num1
	movss xmm2, t
	
	;xmm3 = 1 - t
	movss xmm3, _1
	subss xmm3, xmm2
	
	;num0 * (1 - t)
	mulss xmm0, xmm3
	
	;num1 * t
	mulss xmm1, xmm2

	;num0 * t + num1 * (1 - t)
	addss xmm0, xmm1
endm

_magnitude macro vecX, vecY
	movss xmm0, vecX
	movss xmm1, vecY
	
	;a^2
	mulss xmm0, xmm0
	;b^2
	mulss xmm1, xmm1

	;a^2 + b^2
	addss xmm0, xmm1
	
	;sqrt(a^2 + b^2)
	sqrtss xmm0, xmm0
endm

; used for mixing the normalized velocities of cohesian, separation, etc by their respective weights
_applyRuleToGoalVel macro weight
	; normalize
	call Normalize

	; apply rule weight
	mulss xmm0, weight
	mulss xmm1, weight

	; add to final velocity
	movss xmm9, goalVelHolder.x
	addss xmm9, xmm0
	movss goalVelHolder.x, xmm9

	movss xmm9, goalVelHolder.y
	addss xmm9, xmm1
	movss goalVelHolder.y, xmm9
endm

;takes 2 floats and packs them into first to elements of xmm0. 
;This is here because I was planning on converting this program to use the packed feature of xmm registers but I never got the chance.
_packFloats macro float1, float2
	movss xmm0, ZERO
	movss xmm1, ZERO
	movss xmm0, float1; assign first float in both xmm to respective floats
	movss xmm1, float2
	PSLLDQ xmm1, 4; shift right once
	POR xmm0, xmm1; combine into xmm0
endm

.DATA
align 16

;Structs
vec struct ; I wasn't sure if I should make this an array, but being able to say vec.x was convenient
	x real4 ?
	y real4 ?
vec ends

boid struct
	;personal data
	position vec <?, ?>
	velocity vec <?, ?>
	rotation real4 ?
	
	;neighbor data
	averagePosition vec <?, ?>
	averageVelocity vec <?, ?>
	neighborCount real4 ? ; this is a float, just to make dividing things to get averages easier
boid ends

;Data
;;;;;;;;;;;;;;;;;;; settings
boidSightRange real4 100.0
boidSpeed real4 100.0
boidVelLerpSpeed real4 20.0
maxNeighborsToCohere real4 20.0

cohesianWeight real4 2.0
seperationWeight real4 1.5
seekWeight real4 0.0
fleeWeight real4 0.0
alignWeight real4 1.0
avoidBordersWeight real4 0.0 ; they wrap the screen if avoidBordersWeight isn't strong enough to keep them on screen

borderThickness real4 50.0 ; how close to border before avoidBorder rule kicks in
;;;;;;;;;;;;;;;;;;; settings

;constants.
MAX_BOIDS equ 1000

BOID_SIZE EQU 40; Boid is 40 bytes according to sizeof which is apparently available in assembly
BOID_WIDTH REAL4 ?

Rad2Deg real4 57.29577951; = 180 / PI
Deg2Rad real4 0.01745329; = PI / 180

; I have this here because when you drag the window, the simulation pauses but time doesn't and it ends up screwing up the simulation by sending a huge deltaTime.
MAX_DELTA_TIME real4 0.0166666667 ; aproximately 60 fps. 

;Initially I was using things like fld1 and fldz but it was messing up SFML and would cause it to only draw the first boid. 
;I guess that's because it uses the data in the fpu but I would think they would account for other parts of the program
;using the fpu and therefore backing up the data as needed. But then again I don't know what I'm talking about and I'm
;probably using the fpu wrong.
_1 real4 1.0;
_Neg1 real4 -1.0; okay this was probably a bit overkill...
_90 real4 90.0;

;variables
;some of the operations didn't seem to work with registers, so I use this for those cases
floatHolder real4 ?

boidList boid MAX_BOIDS DUP (<<0.0, 0.0>, <0.0, 0.0>, 0.0>)
currentBoidCount dword 0 

goalVelHolder vec <?, ?>

WINDOW_HEIGHT real4 ?
WINDOW_WIDTH real4 ?

;Input and frame data
mouseDownThisFrame dword 0
mouseDownLastFrame dword 0
mousePosition vec <0.0, 0.0>
deltaTime real4 0.0

.CODE
AsmInit PROC
	;Prologue
	push rbp
	push rdi
	sub rsp, 148h
	lea rbp, [rsp + 32]
	
	;Function's code
	movss WINDOW_HEIGHT, xmm1
	movss WINDOW_WIDTH, xmm0
	movss BOID_WIDTH, xmm3
	
	;Epilogue
	lea rsp, [rbp + 296]
	pop rdi
	pop rbp
	ret
AsmInit Endp


AsmUpdate PROC
	;Prologue
	push rbp
	push rdi
	sub rsp, 148h
	lea rbp, [rsp + 64]

	;Function's code

	;lock framerate 
		comiss xmm0, MAX_DELTA_TIME
		jbe goodFps
		movss xmm0, MAX_DELTA_TIME
		goodFps:
		movss deltaTime, xmm0
		movss mousePosition.x, xmm1
		movss mousePosition.y, xmm2
	
	;hande mouse click
		mov eax, mouseDownThisFrame
		mov mouseDownLastFrame, eax
		mov mouseDownThisFrame, r9d
	
		cmp mouseDownThisFrame, 1
		jne SkipNewBoid; did not click
		mov eax, mouseDownLastFrame
		cmp eax, mouseDownThisFrame
		je SkipNewBoid; mouse is being held. Only make new boid on initial mouse down
		mov eax, currentBoidCount
		cmp currentBoidCount, MAX_BOIDS
		jge SkipNewBoid
		;if (mouse down this frame && mouse not down last frame && less than max boids)
		;{
			mov eax, currentBoidCount
			imul eax, BOID_SIZE
		
			movss xmm0, mousePosition.x
			movss xmm1, mousePosition.y
			movss [boidList + eax].position.x, xmm0
			movss [boidList + eax].position.y, xmm1
			mov edx, currentBoidCount
		
			lea ecx, [boidList + eax]
			mov edx, currentBoidCount
			inc currentBoidCount
			mov r8d, currentBoidCount
			call setBoidData
		;}
	SkipNewBoid:

	call UpdateBoids
	
	; Send boid data to C++ side to draw
		lea ecx, [boidList]
		mov edx, currentBoidCount
		call updateBoidData

	;Epilogue
	lea rsp, [rbp + 264]
	pop rdi
	pop rbp
	ret
AsmUpdate ENDP

;loop through boids and store average location and average velocity of boids within range
UpdateAverageBoidData Proc
	;Prologue
	push rbp
	push rdi
	sub rsp, 148h
	lea rbp, [rsp + 32]
	
	;Function's code
	xor eax, eax
	boidDataLoop:; while (i < currentBoidCount)
	cmp eax, currentBoidCount
	jge quitOuter
		mov edx, eax
		imul edx, BOID_SIZE

			; zero out average data
			xorps xmm0, xmm0
			movss [boidList + edx].averagePosition.x, xmm0
			movss [boidList + edx].averagePosition.y, xmm0
			movss [boidList + edx].averageVelocity.x, xmm0
			movss [boidList + edx].averageVelocity.y, xmm0
			movss [boidList + edx].neighborCount, xmm0
			
			;I use these to store 1 or 0. 1 means to check a cooresponding virtual position (position plus/minus WINDOW_WIDTH/WINDOW_HEIGHT)
			xor r9, r9	 
			xor r10, r10
			xor r11, r11
			xor r12, r12
			mov r13, 1; always test real position

			; is on left side
			movss xmm8, [boidList + edx].position.x
			comiss xmm8, boidSightRange
			ja skipVirtualRight_Test ; if (x < boidSightRange)
			mov r9, 1 ; do virtual test on right side of screen because boids on opposite side should act like they are within range
			jmp skipVirtualLeft_Test; dont bother with testing other side
			skipVirtualRight_Test:

			; is on right side
			movss xmm8, [boidList + edx].position.x
			addss xmm8, boidSightRange
			comiss xmm8, WINDOW_WIDTH
			jb skipVirtualLeft_Test ; if (x > WINDOW_WIDTH - boidSightRange)
			mov r10, 1 ; do virtual test on Left side of screen
			skipVirtualLeft_Test:

			; is on top side
			movss xmm8, [boidList + edx].position.y
			comiss xmm8, boidSightRange
			ja skipVirtualBottom_Test ; if (y < boidSightRange)
			mov r11, 1 ; do virtual test on bottom side of screen because boids on opposite side should act like they are within range
			jmp skipVirtualBot_Test; dont bother with testing other side
			skipVirtualBottom_Test:

			; is on bottom side
			movss xmm8, [boidList + edx].position.y
			addss xmm8, boidSightRange
			comiss xmm8, WINDOW_HEIGHT
			jb skipVirtualBot_Test ; if (y > WINDOW_HEIGHT - boidSightRange)
			mov r12, 1 ; do virtual test on Left side of screen
			skipVirtualBot_Test:
			
			doInnerLoopAgain:
			;Calculate Current Virtual Position
				movss xmm8, [boidList + edx].position.x
				movss xmm9, [boidList + edx].position.y
				
				;do right side virtual test
				cmp r9, 1; if (testRightSide = true)
				jne dontTestRight
				mov r9, 0; dont test 
				addss xmm8, WINDOW_WIDTH ; pos.x + WINDOW_WIDTH
				jmp doTest; skip rest until next iteration
				dontTestRight:

				;do left side virtual test
				cmp r10, 1; if (testLeftSide = true)
				jne dontTestLeft
				mov r10, 0; dont test 
				subss xmm8, WINDOW_WIDTH ; pos.x + WINDOW_WIDTH
				jmp doTest; skip rest until next iteration
				dontTestLeft:
				
				;do bottom side virtual test
				cmp r11, 1; if (testLeftSide = true)
				jne dontTestTop
				mov r11, 0; dont test 
				addss xmm9, WINDOW_HEIGHT ; pos.y + WINDOW_HEIGHT
				jmp doTest; skip rest until next iteration
				dontTestTop:
				
				;do top side virtual test
				cmp r12, 1; if (testLeftSide = true)
				jne dontTestBot
				mov r12, 0; dont test 
				subss xmm9, WINDOW_HEIGHT ; pos.y + WINDOW_HEIGHT
				jmp doTest; skip rest until next iteration
				dontTestBot:			

			doTest:
			xor esi, esi
			boidDataLoopInner: ; while (j < currentBoidCount)
			cmp esi, currentBoidCount
			jge quitInner
				mov edi, esi
				imul edi, BOID_SIZE
				
				;Get distance from current 'ith' boid to current 'jth' boid
				movss xmm5, xmm8
				subss xmm5, [boidList + edi].position.x
				movss xmm6, xmm9
				subss xmm6, [boidList + edi].position.y
				_magnitude xmm5, xmm6

				comiss xmm0, boidSightRange
				ja continueInner ; if to far away, skip boid
					;get total position within range
					movss xmm0, [boidList + edx].averagePosition.x  
					addss xmm0, [boidList + edi].position.x
					movss [boidList + edx].averagePosition.x, xmm0

					movss xmm0, [boidList + edx].averagePosition.y
					addss xmm0, [boidList + edi].position.y
					movss [boidList + edx].averagePosition.y, xmm0

					;get total velocity within range
					movss xmm0, [boidList + edx].averageVelocity.x
					addss xmm0, [boidList + edi].velocity.x
					movss [boidList + edx].averageVelocity.x, xmm0

					movss xmm0, [boidList + edx].averageVelocity.y
					addss xmm0, [boidList + edi].velocity.y
					movss [boidList + edx].averageVelocity.y, xmm0
					
					;increment neighborCount. I assume there is an easier way to do this but inc apparently doesn't work on xmm
					movss xmm0, [boidList + edx].neighborCount
					movss xmm10, _1
					movss floatHolder, xmm10
					addss xmm0, floatHolder
					movss [boidList + edx].neighborCount, xmm0
				continueInner:
			inc esi
			jmp boidDataLoopInner
			quitInner:

			mov r14, r9
			add r14, r10
			add r14, r11
			add r14, r12
			cmp r14, 0; if all virtual positions set to zero, then we've either done them, or didn't need to do them in the first place
			jne doInnerLoopAgain
			cmp r13, 0
			je dontDoInnerLoopAgain
			xor r13, r13 ; do one last loop on actual position
			jmp doInnerLoopAgain
			dontDoInnerLoopAgain:

			;get averages
			CVTSS2SI ebx, [boidList + edx].neighborCount
			cmp ebx, 0; if no neighbors, dont divide by zero
			je skipAvg
				;store neighborCount for division
				movss xmm0, [boidList + edx].neighborCount

				; averagePosition.x = total position.x / neighborCount
				movss xmm1, [boidList + edx].averagePosition.x
				divss xmm1, xmm0
				movss [boidList + edx].averagePosition.x, xmm1
				
				; averagePosition.y = total position.y / neighborCount
				movss xmm1, [boidList + edx].averagePosition.y
				divss xmm1, xmm0
				movss [boidList + edx].averagePosition.y, xmm1
				
				; averageVelocity.x = total velocity.x / neighborCount
				movss xmm1, [boidList + edx].averageVelocity.x
				divss xmm1, xmm0
				movss [boidList + edx].averageVelocity.x, xmm1
				
				; averageVelocity.y = total velocity.y / neighborCount
				movss xmm1, [boidList + edx].averageVelocity.y
				divss xmm1, xmm0 
				movss [boidList + edx].averageVelocity.y, xmm1
			skipAvg:
	inc eax
	jmp boidDataLoop
	quitOuter:
	
	;Epilogue
	lea rsp, [rbp + 296]
	pop rdi
	pop rbp
	ret
UpdateAverageBoidData  ENDP

UpdateBoids PROC
	;Prologue
	push rbp
	push rdi
	sub rsp, 148h
	lea rbp, [rsp + 32]
	
	;Function's code
	call UpdateAverageBoidData

	xor ebx, ebx
	UpdateBoidLoop:
	cmp ebx, currentBoidCount
	jge quitBoidLoop
		;calculate goal vel via ruleset
		
		mov edx, ebx
		imul edx, BOID_SIZE
		
		;zero out goalVel
		xorps xmm0, xmm0
		movss goalVelHolder.x, xmm0
		movss goalVelHolder.y, xmm0
		; seperation. go away from average location within range
			movss xmm0, [boidList + edx].position.x
			movss xmm1, [boidList + edx].position.y
			subss xmm0, [boidList + edx].averagePosition.x
			subss xmm1, [boidList + edx].averagePosition.y
			
			;calculate additional seperation weight based on how close to averageLocation and how many neighbors
				;backup 
				movss xmm2, xmm0
				movss xmm3, xmm1

				_magnitude xmm2, xmm3

				;subtract distance from site range
				movss xmm4, boidSightRange
				subss xmm4, xmm0
				;divide difference by site range
				divss xmm4, boidSightRange

				;get percent of max neighbors
				movss xmm5, [boidList + edx].neighborCount
				divss xmm5, maxNeighborsToCohere

				;add percent to new weight
				addss xmm5, xmm4

			;_applyRuleToGoalVel cant use the macro because of the second weight being applied
			; normalize
			movss xmm0, xmm2
			movss xmm1, xmm3
			call Normalize

			; apply rule weight
			mulss xmm0, seperationWeight
			mulss xmm1, seperationWeight
			
			; apply second rule weight
			mulss xmm0, xmm5
			mulss xmm1, xmm5

			; add to final velocity
			movss xmm9, goalVelHolder.x
			addss xmm9, xmm0
			movss goalVelHolder.x, xmm9

			movss xmm9, goalVelHolder.y
			addss xmm9, xmm1
			movss goalVelHolder.y, xmm9
			
		; cohesian. go towards average location within range
			movss xmm0, [boidList + edx].averagePosition.x
			movss xmm1, [boidList + edx].averagePosition.y
			subss xmm0, [boidList + edx].position.x
			subss xmm1, [boidList + edx].position.y
		
			_applyRuleToGoalVel cohesianWeight
			
		; seek. seek mouse pointer
			movss xmm0, mousePosition.x
			movss xmm1, mousePosition.y
			subss xmm0, [boidList + edx].position.x
			subss xmm1, [boidList + edx].position.y

			movss xmm2, xmm0
			movss xmm3, xmm1
			_magnitude xmm2, xmm3
			comiss xmm0, boidSightRange
			ja skipSeek;if (mouse within range)
			movss xmm0, xmm2
			movss xmm1, xmm3
			_applyRuleToGoalVel seekWeight
			skipSeek:

		; flee. flee mouse pointer
			movss xmm0, [boidList + edx].position.x
			movss xmm1, [boidList + edx].position.y
			subss xmm0, mousePosition.x
			subss xmm1, mousePosition.y
		
			movss xmm2, xmm0
			movss xmm3, xmm1
			_magnitude xmm0, xmm1
			comiss xmm0, boidSightRange
			ja skipFlee;if (mouse within range)
			movss xmm0, xmm2
			movss xmm1, xmm3
			_applyRuleToGoalVel fleeWeight
			skipFlee:

		; align. move in average direction of neighbors. I love it when things take next to no effort to write
			movss xmm0, [boidList + edx].averageVelocity.x
			movss xmm1, [boidList + edx].averageVelocity.y
			
			_applyRuleToGoalVel alignWeight

		; avoid borders. move away from window border.
			movss xmm2, [boidList + edx].position.x
			movss xmm3, [boidList + edx].position.y
			xorps xmm0, xmm0
			xorps xmm1, xmm1

			; calculate horizontal walls
				;calcLeftSide
				comiss xmm2, borderThickness 
				ja calcRightSide; if (x < borderSiteRange)
				;{
					xorps xmm4, xmm4
					comiss xmm2, xmm4
					jae skipInvertBorderLeft; if (x < 0) force positive so to push right. I admit, I was too lazy to try and figure out how to get absolute value of a float. This took less thinking
					;{
						mulss xmm2, _Neg1
					;}
					skipInvertBorderLeft:
					movss xmm0, xmm2
					divss xmm0, borderThickness 
					jmp calcTopSide; dont bother calculating right side
				;}

				calcRightSide:
				movss xmm4, WINDOW_WIDTH
				subss xmm4, xmm2
				comiss xmm4, borderThickness 
				ja calcTopSide; else if (borderSiteRange >= WINDOW_WIDTH - x)
				;{
					xorps xmm5, xmm5
					comiss xmm4, xmm5
					jbe skipInvertBorderRight; if (WINDOW_WIDTH - x > 0) force negative so to push left
					;{
						mulss xmm2, _Neg1
					;}
					skipInvertBorderRight:
					movss xmm0, xmm2
					divss xmm0, borderThickness 
				;}

			; calculate vertical walls
				calcTopSide:
				comiss xmm3, borderThickness 
				ja calcBotSide; if (y < borderSiteRange)
				;{
					xorps xmm4, xmm4
					comiss xmm3, xmm4
					jae skipInvertBorderTop; if (y < 0) force positive so to push down because apparently up is down
					;{
						mulss xmm3, _Neg1
					;}
					skipInvertBorderTop:
					movss xmm1, xmm3
					divss xmm1, borderThickness 
				;}

				calcBotSide:
				movss xmm4, WINDOW_HEIGHT
				subss xmm4, xmm3
				comiss xmm4, borderThickness 
				ja applyBorderRule; else if (borderSiteRange >= WINDOW_WIDTH - y)
				;{
					xorps xmm5, xmm5
					comiss xmm4, xmm5
					jbe skipInvertBorderBot; if (WINDOW_WIDTH - y > 0) force negative so to push up
					;{
						mulss xmm3, _Neg1
					;}
					skipInvertBorderBot:
					movss xmm1, xmm3
					divss xmm1, borderThickness 
				;}

			applyBorderRule:
			_applyRuleToGoalVel avoidBordersWeight

		; normalize total velocity
		movss xmm0, goalVelHolder.x
		movss xmm1, goalVelHolder.y
		call Normalize
		
		;scale unit velocity by boidSpeed
		mulss xmm0, boidSpeed
		mulss xmm1, boidSpeed
		
		;scale by time passed this frame
		mulss xmm0, deltaTime
		mulss xmm1, deltaTime

		;set new velocity 
		movss goalVelHolder.x, xmm0
		movss goalVelHolder.y, xmm1
		
		;calculate t for velocity lerp
			movss xmm1, boidVelLerpSpeed
			mulss xmm1, deltaTime
			movss floatHolder, xmm1

		;lerp old velocity last frame to new velocity
			_lerpFloat [boidList + edx].velocity.x, goalVelHolder.x, floatHolder; lerp vel.x
			;movss xmm0, goalVelHolder.x
			movss [boidList + edx].velocity.x, xmm0
			_lerpFloat [boidList + edx].velocity.y, goalVelHolder.y, floatHolder; lerp vel.y
			;movss xmm0, goalVelHolder.y
			movss [boidList + edx].velocity.y, xmm0
		
		;Set new position = position + final velocity
			movss xmm1, [boidList + edx].position.x
			addss xmm1, [boidList + edx].velocity.x

		;do screen wrap
			;testRightSide
			movss xmm2, WINDOW_WIDTH
			addss xmm2, BOID_WIDTH
			comiss xmm1, xmm2
			jb testLeftSide; if (x >= WINDOW_WIDTH + BOID_WIDTH)
			;{
				movss xmm3, [boidList + edx].velocity.x
				xorps xmm4, xmm4
				comiss xmm3, xmm4
				jb testLeftSide; if (velocity.x > 0)
				;{
					;jump to left side - BOID_WIDTH
					xorps xmm2, xmm2
					subss xmm2, BOID_WIDTH
					movss xmm1, xmm2
					jmp applyAdjustedXPosition
				;}
			;}

			testLeftSide:
			xorps xmm2, xmm2
			subss xmm2, BOID_WIDTH
			comiss xmm1, xmm2
			ja applyAdjustedXPosition; if (x <= -BOID_WIDTH)
			;{
				movss xmm3, [boidList + edx].velocity.x
				xorps xmm4, xmm4
				comiss xmm3, xmm4
				ja applyAdjustedXPosition; if (velocity.x < 0)
				;{
					;jump to right side + BOID_WIDTH
					xorps xmm2, xmm2
					addss xmm2, BOID_WIDTH
					addss xmm2, WINDOW_WIDTH
					movss xmm1, xmm2
					jmp applyAdjustedXPosition
				;}
			;}
			
			applyAdjustedXPosition:
			movss [boidList + edx].position.x, xmm1

			testVertSides:
			movss xmm1, [boidList + edx].position.y
			addss xmm1, [boidList + edx].velocity.y
			
			;testBotSide
			movss xmm2, WINDOW_HEIGHT
			addss xmm2, BOID_WIDTH
			comiss xmm1, xmm2
			jb testTopSide; if (y >= WINDOW_HEIGHT + BOID_WIDTH)
			;{
				movss xmm3, [boidList + edx].velocity.y
				xorps xmm4, xmm4
				comiss xmm3, xmm4
				jb testTopSide; if (velocity.x > 0)
				;{
					;jump to left side - BOID_WIDTH
					xorps xmm2, xmm2
					subss xmm2, BOID_WIDTH
					movss xmm1, xmm2
					jmp applyAdjustedYPosition
				;}
			;}

			testTopSide:
			xorps xmm2, xmm2
			subss xmm2, BOID_WIDTH
			comiss xmm1, xmm2
			ja applyAdjustedYPosition; if (y <= -BOID_WIDTH)
			;{
				movss xmm3, [boidList + edx].velocity.y
				xorps xmm4, xmm4
				comiss xmm3, xmm4
				ja applyAdjustedYPosition; if (velocity.y < 0)
				;{
					;jump to right side + BOID_WIDTH
					xorps xmm2, xmm2
					addss xmm2, BOID_WIDTH
					addss xmm2, WINDOW_HEIGHT
					movss xmm1, xmm2
					jmp applyAdjustedYPosition
				;}
			;}
			
			applyAdjustedYPosition:
			movss [boidList + edx].position.y, xmm1

		;Calculate look direction based on velocity. Doesn't work in release mode
			movss xmm0, [boidList + edx].velocity.y
			movss xmm1, [boidList + edx].velocity.x
			call Atan2
			mulss xmm0, Rad2Deg
			addss xmm0, _90
		
		movss [boidList + edx].rotation, xmm0

	inc ebx
	jmp UpdateBoidLoop
	quitBoidLoop:

	;Epilogue
	lea rsp, [rbp + 296]
	pop rdi
	pop rbp
	ret
UpdateBoids ENDP

;Initially this was a macro, but then I realized I couldn't use the labels for jumping, since it would be copying them everywhere I use the macro and therfore be technically redefined in those places
Normalize Proc
	;Prologue
	push rbp
	push rdi
	sub rsp, 148h
	lea rbp, [rsp + 32]
	
	;Function's code

	;backup for normalize
	movss xmm2, xmm0
	movss xmm3, xmm1

	_magnitude xmm0, xmm1
	
	xorps xmm4, xmm4
	movss floatHolder, xmm4
	comiss xmm0, floatHolder
	jbe skipNormalizeDivide
	;if (magnitude > 0)
	;{
		;x / magnitude
		divss xmm2, xmm0
		;y / magnitude
		divss xmm3, xmm0
	;}
	skipNormalizeDivide:

	movss xmm0, xmm2
	movss xmm1, xmm3

	;Epilogue
	lea rsp, [rbp + 296]
	pop rdi
	pop rbp
	ret
Normalize ENDP
END