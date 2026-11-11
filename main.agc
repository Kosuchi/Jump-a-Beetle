// =====================================================================
//  UP'N DOWN PROTOTYPE  (AppGameKit Tier 1 / AGK Script)
//  No external resources: all graphics are drawn into memory in code (memblocks).
//  View: behind-the-car pseudo-3D (hills rise and fall, the road winds).
//
//  CONTROLS: Up / W = accelerate     Down / S = brake
//            Left / Right / A / D = change lane
//            Space / Z = jump (only on the ground)
//            Enter = restart (Game Over / win)
//            M = sound on / off
//
//  RULES:    - Hitting an enemy on the ground   -> your car is destroyed
//            - Landing on top of an enemy       -> the enemy is squashed (+500)
//            - Landing on grass                 -> your car is destroyed
//            - Collect all 8 flags and cross the finish line.
//  NOTE: While jumping you can steer to lane +-2 (= off the road).
// =====================================================================

// ---------------- Display ----------------
SetWindowTitle("Up'n Down - AGK prototype")
SetWindowSize(540, 960, 0)
SetWindowAllowResize(1)
SetVirtualResolution(720, 1280)
SetOrientationAllowed(1, 1, 0, 0)
SetSyncRate(60, 0)
SetScissor(0, 0, 0, 0)
SetClearColor(30, 120, 30)
SetRandomSeed(GetSeconds())

// ---------------- Constants ----------------
#constant SW              720
#constant SH              1280
#constant TRACK_LEN       14000      // track length in pixels
#constant ROAD_W          520        // road width
#constant LANE_W          150        // lane width
#constant SEG             32         // road segment length in the world
#constant NUM_ROWS        120        // number of road segments (draw distance)
// Pseudo-3D camera (behind the car; hills and curves in perspective)
#constant PERSP_F    520.0       // perspective strength
#constant HORIZON_Y  470         // horizon position on screen
#constant PLAYER_SY  1040        // player car position on screen (Y)
#constant ZFAR       3600.0      // draw distance
#constant CURVE_K    1.6         // curve exaggeration
#constant HILL_AMP   80.0        // hill height
#constant HILL_K     1.8         // hill exaggeration on screen
#constant TREE_STEP  220         // tree spacing
#constant NUM_TREES  20
#constant HAZE_R     120         // horizon haze colour
#constant HAZE_G     170
#constant HAZE_B     120
#constant MAX_ENEMIES     5          // 6 enemies (0..5) - decrease/increase to change difficulty
#constant NUM_FLAGS       8
#constant NUM_BONUS       6
#constant MAX_ITEMS       13         // 14 items (0..13)
#constant MAX_PART        39         // 40 particles

// Player state machine
#constant STATE_GROUNDED  0
#constant STATE_JUMPING   1
#constant STATE_CRASHED   2

// Game state
#constant GAME_PLAY       0
#constant GAME_OVER       1
#constant GAME_WON        2

// Images
#constant IMG_WHITE   1
#constant IMG_PLAYER  5
#constant IMG_ENEMY0  6
#constant IMG_ENEMY1  7
#constant IMG_ENEMY2  8
#constant IMG_SHADOW  9
#constant IMG_FLAG    10
#constant IMG_BONUS   11
#constant IMG_FINISH  12
#constant IMG_PART    13
#constant IMG_TREE    14
#constant IMG_MOUNT   15

// Sounds (generated in code into memblocks, no sound files)
#constant SAMPLE_RATE 22050
#constant SND_JUMP     1
#constant SND_LAND     2
#constant SND_CRASH    3
#constant SND_SQUASH   4
#constant SND_FLAG     5
#constant SND_BONUS    6
#constant SND_RESPAWN  7
#constant SND_ENGINE   8
#constant SND_MUSIC    9
#constant SND_WIN      10
#constant SND_GAMEOVER 11

// ---------------- Data types ----------------
type tEnemy
    kind   as integer      // 0 = slow, 1 = fast, 2 = oncoming
    x      as float
    y      as float
    spd    as float        // positive = upward (Y decreases)
    lane   as integer
    active as integer      // 0 = off, 1 = alive, 2 = squashed
    timer  as integer
    spr    as integer
endtype

type tItem
    y      as float
    lane   as integer
    got    as integer
    kind   as integer      // 0 = flag, 1 = bonus
    spr    as integer
endtype

// ---------------- Global variables ----------------
global gameState    as integer
global playerState  as integer
global score        as integer
global lives        as integer
global flagsGot     as integer
global crashTimer   as integer
global invuln       as integer
global msgTimer     as integer
global message$     as string

global playerX      as float
global playerY      as float
global offX         as float
global laneTarget   as integer
global speed        as float
global camY         as float

// Pseudo-3D projection
global playerElev   as float
global roadCP       as float
global camLat       as float
global gSX          as float
global gSY          as float
global gS           as float
global rowBase      as integer
global dim edgeY[NUM_ROWS] as float
global dim edgeX[NUM_ROWS] as float
global dim edgeS[NUM_ROWS] as float
global dim treeSpr[NUM_TREES] as integer
global dim skySpr[7] as integer
global sprGround    as integer
global sprMount     as integer

// Drawing an image into a memblock
global imgMem       as integer
global imgW         as integer
global imgH         as integer

// Jump physics
global is_jumping   as integer
global jump_height  as float
global jump_speed_z as float
global gravity_z    as float

// Sprites and texts
global sprPlayer    as integer
global sprShadow    as integer
global sprBG        as integer
global sprFinish    as integer
global txtScore     as integer
global txtLives     as integer
global txtSpeed     as integer
global txtFlags     as integer
global txtSlope     as integer
global txtMsg       as integer
global txtKeys      as integer

global dim roadSpr[NUM_ROWS]  as integer
global dim grassSpr[NUM_ROWS] as integer
global dim kerbSpr[NUM_ROWS]  as integer
global dim markLSpr[NUM_ROWS] as integer
global dim markRSpr[NUM_ROWS] as integer

global dim enemies[MAX_ENEMIES] as tEnemy
global dim items[MAX_ITEMS]     as tItem

global dim partSpr[MAX_PART]  as integer
global dim partX[MAX_PART]    as float
global dim partY[MAX_PART]    as float      // height above the ground
global dim partWY[MAX_PART]   as float      // world Y
global dim partVX[MAX_PART]   as float
global dim partVY[MAX_PART]   as float
global dim partLife[MAX_PART] as integer

// Audio
global engineInst   as integer
global muted        as integer
global dim noteFreq[127] as float

gravity_z = 0.55          // jump gravity

CreateWorld()
InitAudio()
ResetGame()

// =====================================================================
//  MAIN LOOP
// =====================================================================
do
    if gameState = GAME_PLAY
        UpdateGame()
    else
        UpdateGameParticles()
        if GetRawKeyPressed(13) = 1 then ResetGame()
    endif
    UpdateVisuals()
    UpdateAudio()
    Sync()
loop

// =====================================================================
//  HELPER FUNCTIONS: ROAD AND HILLS
// =====================================================================

// X coordinate of the road centreline at world Y (winding road)
function RoadCenter(y#)
    r# = 360.0 + sin(y# * 0.22) * 110.0
endfunction r#

// Slope steepness: positive = downhill, negative = uphill
// (AGK's sin() uses degrees)
function Slope(y#)
    s# = sin(y# * 0.30)
endfunction s#

// =====================================================================
//  CREATION: images, sprites, texts
// =====================================================================
function CreateWorld()
    local i as integer
    local t# as float
    local rd as integer

    // --- Images (drawn in code, no external files) ---
    CreateImageColor(IMG_WHITE, 255, 255, 255, 255)
    MakeCarImage(IMG_PLAYER,  40, 190,  70)     // player: green
    MakeCarImage(IMG_ENEMY0, 215,  35,  35)     // red
    MakeCarImage(IMG_ENEMY1, 175,  45, 175)     // purple (fast)
    MakeCarImage(IMG_ENEMY2, 240, 140,  25)     // orange (oncoming)
    MakeShadowImage(IMG_SHADOW)
    MakeFlagImage(IMG_FLAG)
    MakeCoinImage(IMG_BONUS)
    MakeGateImage(IMG_FINISH)
    MakeParticleImage(IMG_PART)
    MakeTreeImage(IMG_TREE)
    MakeMountainImage(IMG_MOUNT)

    // --- Sky (stepped gradient), hazy ground and mountains ---
    for i = 0 to 7
        t# = i / 7.0
        skySpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteSize(skySpr[i], SW, HORIZON_Y / 8 + 2)
        SetSpritePosition(skySpr[i], 0, i * (HORIZON_Y / 8))
        SetSpriteColor(skySpr[i], 40 + 130 * t#, 100 + 115 * t#, 215 + 30 * t#, 255)
        SetSpriteDepth(skySpr[i], 9000)
    next i

    sprGround = CreateSprite(IMG_WHITE)
    SetSpriteSize(sprGround, SW, SH - HORIZON_Y)
    SetSpritePosition(sprGround, 0, HORIZON_Y)
    SetSpriteColor(sprGround, HAZE_R, HAZE_G, HAZE_B, 255)
    SetSpriteDepth(sprGround, 8999)

    sprMount = CreateSprite(IMG_MOUNT)
    SetSpriteSize(sprMount, SW, 80)
    SetSpritePosition(sprMount, 0, HORIZON_Y + 2 - 80)
    SetSpriteDepth(sprMount, 8998)

    // --- Road segments: grass, curbs, road, lane markings ---
    for i = 0 to NUM_ROWS - 1
        rd = 6000 - i * 10               // far = large depth, near = small
        grassSpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteDepth(grassSpr[i], rd + 4)
        kerbSpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteDepth(kerbSpr[i], rd + 3)
        roadSpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteDepth(roadSpr[i], rd + 2)
        markLSpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteDepth(markLSpr[i], rd + 1)
        markRSpr[i] = CreateSprite(IMG_WHITE)
        SetSpriteDepth(markRSpr[i], rd + 1)
    next i

    // --- Trees along the road ---
    for i = 0 to NUM_TREES - 1
        treeSpr[i] = CreateSprite(IMG_TREE)
        SetSpriteSize(treeSpr[i], 90, 135)
    next i

    // --- Finish gate ---
    sprFinish = CreateSprite(IMG_FINISH)
    SetSpriteSize(sprFinish, ROAD_W + 80, 240)

    // --- Player and shadow ---
    sprShadow = CreateSprite(IMG_SHADOW)
    SetSpriteSize(sprShadow, 100, 30)
    sprPlayer = CreateSprite(IMG_PLAYER)
    SetSpriteSize(sprPlayer, 96, 86)

    // --- Enemies ---
    for i = 0 to MAX_ENEMIES
        enemies[i].spr = CreateSprite(IMG_ENEMY0)
        SetSpriteSize(enemies[i].spr, 96, 86)
        enemies[i].active = 0
    next i

    // --- Flags and bonuses ---
    for i = 0 to MAX_ITEMS
        if i < NUM_FLAGS
            items[i].kind = 0
            items[i].spr = CreateSprite(IMG_FLAG)
        else
            items[i].kind = 1
            items[i].spr = CreateSprite(IMG_BONUS)
        endif
        SetSpriteSize(items[i].spr, 40, 40)
    next i

    // --- Particles ---
    for i = 0 to MAX_PART
        partSpr[i] = CreateSprite(IMG_PART)
        SetSpriteSize(partSpr[i], 12, 12)
        SetSpriteDepth(partSpr[i], 40)
        SetSpriteVisible(partSpr[i], 0)
        partLife[i] = 0
    next i

    // --- HUD ---
    txtScore = CreateText("")
    SetTextSize(txtScore, 36)
    SetTextPosition(txtScore, 20, 15)
    SetTextColor(txtScore, 255, 255, 255, 255)
    FixTextToScreen(txtScore, 1)
    SetTextDepth(txtScore, 10)

    txtLives = CreateText("")
    SetTextSize(txtLives, 36)
    SetTextPosition(txtLives, 20, 60)
    SetTextColor(txtLives, 255, 255, 255, 255)
    FixTextToScreen(txtLives, 1)
    SetTextDepth(txtLives, 10)

    txtFlags = CreateText("")
    SetTextSize(txtFlags, 36)
    SetTextPosition(txtFlags, 20, 105)
    SetTextColor(txtFlags, 255, 230, 0, 255)
    FixTextToScreen(txtFlags, 1)
    SetTextDepth(txtFlags, 10)

    txtSpeed = CreateText("")
    SetTextSize(txtSpeed, 36)
    SetTextAlignment(txtSpeed, 2)
    SetTextPosition(txtSpeed, SW - 20, 15)
    SetTextColor(txtSpeed, 255, 255, 255, 255)
    FixTextToScreen(txtSpeed, 1)
    SetTextDepth(txtSpeed, 10)

    txtSlope = CreateText("")
    SetTextSize(txtSlope, 30)
    SetTextAlignment(txtSlope, 2)
    SetTextPosition(txtSlope, SW - 20, 60)
    SetTextColor(txtSlope, 255, 255, 255, 255)
    FixTextToScreen(txtSlope, 1)
    SetTextDepth(txtSlope, 10)

    txtKeys = CreateText("")
    SetTextSize(txtKeys, 24)
    SetTextPosition(txtKeys, 20, 1235)
    SetTextColor(txtKeys, 255, 255, 255, 220)
    FixTextToScreen(txtKeys, 1)
    SetTextDepth(txtKeys, 10)

    txtMsg = CreateText("")
    SetTextSize(txtMsg, 44)
    SetTextAlignment(txtMsg, 1)
    SetTextPosition(txtMsg, SW / 2, 520)
    SetTextColor(txtMsg, 255, 255, 255, 255)
    FixTextToScreen(txtMsg, 1)
    SetTextDepth(txtMsg, 5)
endfunction

// =====================================================================
//  GAME INITIALISATION / RESTART
// =====================================================================
function ResetGame()
    local i as integer

    gameState    = GAME_PLAY
    playerState  = STATE_GROUNDED
    score        = 0
    lives        = 3
    flagsGot     = 0
    crashTimer   = 0
    invuln       = 0
    playerY      = 0.0
    offX         = 0.0
    laneTarget   = 0
    speed        = 0.0
    is_jumping   = 0
    jump_height  = 0.0
    jump_speed_z = 0.0

    SetSpriteColor(sprPlayer, 255, 255, 255, 255)

    // Flags and bonuses are placed on the track
    for i = 0 to MAX_ITEMS
        items[i].got  = 0
        items[i].lane = Random(0, 2) - 1
        if i < NUM_FLAGS
            items[i].y = 0.0 - (1200 + i * 1500)
        else
            items[i].y = 0.0 - (900 + (i - NUM_FLAGS) * 2000)
        endif
    next i

    for i = 0 to MAX_ENEMIES
        SpawnEnemy(i)
    next i

    for i = 0 to MAX_PART
        partLife[i] = 0
        SetSpriteVisible(partSpr[i], 0)
    next i

    message$ = "Collect all the flags" + chr(10) + "and drive to the finish!"
    msgTimer = 180

    StartMusic()
endfunction

// Create (or recycle) an enemy ahead of the player
function SpawnEnemy(i as integer)
    local k as integer
    k = Random(0, 2)
    enemies[i].kind   = k
    enemies[i].lane   = Random(0, 2) - 1
    enemies[i].y      = FindSpawnY(i)
    enemies[i].active = 1
    enemies[i].timer  = 0
    if k = 0
        enemies[i].spd = 2.5
        SetSpriteImage(enemies[i].spr, IMG_ENEMY0)
    elseif k = 1
        enemies[i].spd = 4.0
        SetSpriteImage(enemies[i].spr, IMG_ENEMY1)
    else
        enemies[i].spd = -3.0          // oncoming car drives downward
        SetSpriteImage(enemies[i].spr, IMG_ENEMY2)
    endif
    SetSpriteColor(enemies[i].spr, 255, 255, 255, 255)
    SetSpriteVisible(enemies[i].spr, 1)
endfunction

// =====================================================================
//  MAIN UPDATE (game logic)
// =====================================================================
function UpdateGame()
    local sl# as float
    local maxSp# as float
    local i as integer

    sl# = Slope(playerY)

    if invuln > 0 then invuln = invuln - 1
    if msgTimer > 0 then msgTimer = msgTimer - 1

    if playerState = STATE_CRASHED
        // ---- Crashed: waiting for respawn ----
        crashTimer = crashTimer - 1
        if mod(crashTimer, 4) = 0
            SpawnParticles(playerX, playerY, 120, 120, 120, 2)
        endif
        if crashTimer <= 0
            if lives <= 0
                gameState = GAME_OVER
                message$ = "GAME OVER" + chr(10) + "Enter = new game"
                msgTimer = 99999
                StopSound(SND_MUSIC)
                PlaySound(SND_GAMEOVER, 85, 0)
            else
                RespawnPlayer()
            endif
        endif
    else
        // ---- Acceleration / braking ----
        maxSp# = 9.5 + sl# * 3.0            // higher top speed downhill
        if is_jumping = 0
            if KeyUp() = 1
                speed = speed + 0.16 + sl# * 0.05
            elseif KeyDown() = 1
                speed = speed - 0.35
            else
                speed = speed - 0.04
            endif
            speed = speed + sl# * 0.06      // gravity on slopes
            if speed > maxSp# then speed = speed - 0.2
            if speed > 12.0 then speed = 12.0
            if speed < 0.0 then speed = 0.0
        endif

        // ---- Lane change ----
        if KeyLeftPressed() = 1 then laneTarget = laneTarget - 1
        if KeyRightPressed() = 1 then laneTarget = laneTarget + 1
        if is_jumping = 0
            // on the ground you stay on the road
            if laneTarget < -1 then laneTarget = -1
            if laneTarget > 1 then laneTarget = 1
        else
            // in the air you can steer off the road
            if laneTarget < -2 then laneTarget = -2
            if laneTarget > 2 then laneTarget = 2
        endif
        offX = offX + (laneTarget * LANE_W - offX) * 0.15

        // ---- Movement ----
        playerY = playerY - speed
        playerX = RoadCenter(playerY) + offX

        // ---- Jump ----
        if KeyJumpPressed() = 1 and is_jumping = 0
            is_jumping = 1
            playerState = STATE_JUMPING
            jump_height = 0.0
            jump_speed_z = 7.0 + speed * 0.55     // jump height/length depends on speed
            PlaySound(SND_JUMP, 70, 0)
        endif

        if is_jumping = 1
            jump_height = jump_height + jump_speed_z
            jump_speed_z = jump_speed_z - gravity_z
            if jump_height <= 0.0 and jump_speed_z < 0.0
                jump_height = 0.0
                is_jumping = 0
                playerState = STATE_GROUNDED
                HandleLanding()
            endif
        endif

        // ---- Ground contact with an enemy ----
        if playerState = STATE_GROUNDED and invuln = 0
            for i = 0 to MAX_ENEMIES
                if enemies[i].active = 1
                    if abs(enemies[i].x - playerX) < 52 and abs(enemies[i].y - playerY) < 85
                        CrashPlayer("Crash!")
                        exit
                    endif
                endif
            next i
        endif

        // ---- Item pickup (only when the car is low) ----
        if playerState <> STATE_CRASHED and jump_height < 25.0
            CollectItems()
        endif

        // ---- Finish line ----
        if playerY < 0.0 - TRACK_LEN
            if flagsGot >= NUM_FLAGS
                gameState = GAME_WON
                message$ = "YOU WIN!  Score: " + str(score) + chr(10) + "Enter = new game"
                msgTimer = 99999
                StopSound(SND_MUSIC)
                PlaySound(SND_WIN, 90, 0)
            else
                // Flags missing -> the lap starts again
                playerY = playerY + TRACK_LEN
                for i = 0 to MAX_ENEMIES
                    enemies[i].y = enemies[i].y + TRACK_LEN
                next i
                message$ = "Flags missing!" + chr(10) + "New lap."
                msgTimer = 150
            endif
        endif
    endif

    UpdateEnemies()
    UpdateGameParticles()
endfunction

// Landing: squashing, grass
function HandleLanding()
    local i as integer
    local hit as integer
    hit = 0
    PlaySound(SND_LAND, 60, 0)

    // Landing off the road
    if abs(offX) > 235.0
        CrashPlayer("Off the road!")
        exitfunction
    endif

    // Landing on top of an enemy
    for i = 0 to MAX_ENEMIES
        if enemies[i].active = 1
            if abs(enemies[i].x - playerX) < 62 and abs(enemies[i].y - playerY) < 95
                enemies[i].active = 2          // squashed
                enemies[i].timer = 40
                score = score + 500
                hit = 1
                PlaySound(SND_SQUASH, 95, 0)
                SpawnParticles(enemies[i].x, enemies[i].y, 255, 200, 40, 10)
                SetSpriteColor(enemies[i].spr, 90, 20, 20, 255)
            endif
        endif
    next i
    if hit = 1
        message$ = "SQUASHED! +500"
        msgTimer = 60
    endif
endfunction

// Player destroyed
function CrashPlayer(why$ as string)
    playerState = STATE_CRASHED
    is_jumping = 0
    jump_height = 0.0
    speed = 0.0
    lives = lives - 1
    crashTimer = 90
    PlaySound(SND_CRASH, 100, 0)
    message$ = why$
    msgTimer = 80
    SetSpriteColor(sprPlayer, 255, 120, 0, 255)
    SpawnParticles(playerX, playerY, 255, 120, 0, 16)
endfunction

// New car on the road
function RespawnPlayer()
    local i as integer
    playerState = STATE_GROUNDED
    is_jumping = 0
    jump_height = 0.0
    offX = 0.0
    laneTarget = 0
    speed = 0.0
    invuln = 120
    PlaySound(SND_RESPAWN, 70, 0)
    SetSpriteColor(sprPlayer, 255, 255, 255, 255)
    // move nearby enemies far ahead
    for i = 0 to MAX_ENEMIES
        if abs(enemies[i].y - playerY) < 700
            SpawnEnemy(i)
        endif
    next i
endfunction

// Collecting flags and bonuses
function CollectItems()
    local i as integer
    local ix# as float
    for i = 0 to MAX_ITEMS
        if items[i].got = 0
            ix# = RoadCenter(items[i].y) + items[i].lane * LANE_W
            if abs(ix# - playerX) < 55 and abs(items[i].y - playerY) < 65
                items[i].got = 1
                if items[i].kind = 0
                    flagsGot = flagsGot + 1
                    score = score + 100
                    PlaySound(SND_FLAG, 80, 0)
                    message$ = "Flag! " + str(flagsGot) + "/" + str(NUM_FLAGS)
                    SpawnParticles(ix#, items[i].y, 255, 230, 0, 6)
                else
                    score = score + 200
                    PlaySound(SND_BONUS, 80, 0)
                    message$ = "Bonus +200"
                    SpawnParticles(ix#, items[i].y, 0, 220, 255, 6)
                endif
                msgTimer = 50
            endif
        endif
    next i
endfunction

// Enemy movement and recycling
function UpdateEnemies()
    local i as integer
    for i = 0 to MAX_ENEMIES
        if enemies[i].active = 1
            enemies[i].y = enemies[i].y - enemies[i].spd
            if enemies[i].y > playerY + 900.0 or enemies[i].y < playerY - 4800.0
                SpawnEnemy(i)
            endif
        elseif enemies[i].active = 2
            enemies[i].timer = enemies[i].timer - 1
            if enemies[i].timer <= 0 then SpawnEnemy(i)
        endif
        enemies[i].x = RoadCenter(enemies[i].y) + enemies[i].lane * LANE_W
    next i
endfunction

// =====================================================================
//  PARTICLES
// =====================================================================
function SpawnParticles(x# as float, y# as float, r as integer, g as integer, b as integer, n as integer)
    local i as integer
    local c as integer
    c = 0
    for i = 0 to MAX_PART
        if c >= n then exit
        if partLife[i] <= 0
            partLife[i] = 25 + Random(0, 15)
            partWY[i] = y#                          // world Y
            partX[i]  = x# - RoadCenter(y#)         // lateral offset from the road centre
            partY[i]  = 18.0                        // height above the ground
            partVX[i] = (Random(0, 100) - 50) * 0.12
            partVY[i] = Random(20, 90) * 0.1        // upward
            SetSpriteColor(partSpr[i], r, g, b, 255)
            SetSpriteVisible(partSpr[i], 1)
            c = c + 1
        endif
    next i
endfunction

function UpdateGameParticles()
    local i as integer
    for i = 0 to MAX_PART
        if partLife[i] > 0
            partLife[i] = partLife[i] - 1
            partX[i]  = partX[i] + partVX[i]
            partY[i]  = partY[i] + partVY[i]
            partVY[i] = partVY[i] - 0.3
            if partY[i] < 0.0
                partY[i] = 0.0
                partVY[i] = 0.0
            endif
            if partLife[i] <= 0 then SetSpriteVisible(partSpr[i], 0)
        endif
    next i
endfunction

// =====================================================================
//  RENDERING / CAMERA / HUD
// =====================================================================
function UpdateVisuals()
    local i as integer
    local e as integer
    local k as integer
    local n as integer
    local sd as integer
    local idx as integer
    local baseT as integer
    local al as integer
    local wy# as float
    local z# as float
    local hh# as float
    local h# as float
    local w# as float
    local y# as float
    local sA# as float
    local xc# as float
    local f# as float
    local shade# as float
    local kw# as float
    local rw# as float
    local mw# as float
    local lat# as float
    local lift# as float
    local shd# as float
    local sl# as float

    // ---- Camera state ----
    playerX    = RoadCenter(playerY) + offX
    playerElev = ElevAt(playerY)
    roadCP     = RoadCenter(playerY)
    camLat     = offX * 0.5
    rowBase    = Floor((playerY - ZFAR) / SEG)

    // ---- Segment edges are projected once ----
    for e = 0 to NUM_ROWS
        wy# = (rowBase + e) * SEG
        ProjectPt(wy#, 0.0, 0.0)
        edgeY[e] = gSY
        edgeX[e] = gSX
        edgeS[e] = gS
    next e

    // ---- Road: each segment is a rectangle between its edges ----
    // Hills: height difference shifts the edges vertically -> the road rises and falls.
    for i = 0 to NUM_ROWS - 1
        hh# = edgeY[i + 1] - edgeY[i]
        if hh# < 0.6
            SetSpriteVisible(grassSpr[i], 0)
            SetSpriteVisible(kerbSpr[i], 0)
            SetSpriteVisible(roadSpr[i], 0)
            SetSpriteVisible(markLSpr[i], 0)
            SetSpriteVisible(markRSpr[i], 0)
        else
            idx = rowBase + i
            sA# = (edgeS[i] + edgeS[i + 1]) * 0.5
            xc# = (edgeX[i] + edgeX[i + 1]) * 0.5
            wy# = (idx + 0.5) * SEG
            z# = playerY - wy#
            f# = z# / ZFAR
            if f# < 0.0 then f# = 0.0
            if f# > 1.0 then f# = 1.0
            f# = f# * f# * 0.95                       // fog in the distance
            shade# = 1.0 + Slope(wy#) * 0.18          // downhill lighter, uphill darker
            h# = hh# + 1.4
            y# = edgeY[i] - 0.4
            k = mod(abs(idx), 8)

            // grass (the striping gives a sense of speed)
            SetSpriteVisible(grassSpr[i], 1)
            if k < 4
                SetRowColor(grassSpr[i], 48, 152, 52, shade#, f#)
            else
                SetRowColor(grassSpr[i], 38, 132, 42, shade#, f#)
            endif
            SetSpriteSize(grassSpr[i], 2700.0, h#)
            SetSpritePosition(grassSpr[i], xc# - 1350.0, y#)

            // curbs (red/white)
            kw# = (ROAD_W + 56) * sA#
            SetSpriteVisible(kerbSpr[i], 1)
            if mod(abs(idx), 4) < 2
                SetRowColor(kerbSpr[i], 238, 238, 238, shade#, f#)
            else
                SetRowColor(kerbSpr[i], 215, 40, 40, shade#, f#)
            endif
            SetSpriteSize(kerbSpr[i], kw#, h#)
            SetSpritePosition(kerbSpr[i], xc# - kw# * 0.5, y#)

            // asphalt
            rw# = ROAD_W * sA#
            SetSpriteVisible(roadSpr[i], 1)
            if k < 4
                SetRowColor(roadSpr[i], 116, 116, 124, shade#, f#)
            else
                SetRowColor(roadSpr[i], 106, 106, 114, shade#, f#)
            endif
            SetSpriteSize(roadSpr[i], rw#, h#)
            SetSpritePosition(roadSpr[i], xc# - rw# * 0.5, y#)

            // dashed lines between lanes
            if mod(abs(idx), 4) < 2
                mw# = 7.0 * sA#
                if mw# < 1.0 then mw# = 1.0
                SetSpriteVisible(markLSpr[i], 1)
                SetSpriteVisible(markRSpr[i], 1)
                SetRowColor(markLSpr[i], 235, 235, 235, shade#, f#)
                SetRowColor(markRSpr[i], 235, 235, 235, shade#, f#)
                SetSpriteSize(markLSpr[i], mw#, h#)
                SetSpriteSize(markRSpr[i], mw#, h#)
                SetSpritePosition(markLSpr[i], xc# - LANE_W * 0.5 * sA# - mw# * 0.5, y#)
                SetSpritePosition(markRSpr[i], xc# + LANE_W * 0.5 * sA# - mw# * 0.5, y#)
            else
                SetSpriteVisible(markLSpr[i], 0)
                SetSpriteVisible(markRSpr[i], 0)
            endif
        endif
    next i

    // ---- Trees ----
    baseT = Floor((playerY - ZFAR - 150.0) / TREE_STEP)
    for k = 0 to NUM_TREES - 1
        n = baseT + k
        wy# = n * TREE_STEP
        z# = playerY - wy#
        if z# < -150.0 or z# > ZFAR
            SetSpriteVisible(treeSpr[k], 0)
        else
            sd = -1
            if mod(abs(n), 2) = 1 then sd = 1
            lat# = sd * (ROAD_W / 2 + 70 + mod(abs(n) * 53, 90))
            ProjectPt(wy#, lat#, 0.0)
            w# = 96.0 * gS
            h# = 144.0 * gS
            SetSpriteSize(treeSpr[k], w#, h#)
            SetSpritePosition(treeSpr[k], gSX - w# * 0.5, gSY - h# * 0.96)
            SetSpriteDepth(treeSpr[k], DepthFor(wy#))
            SetSpriteColor(treeSpr[k], 255, 255, 255, FogAlpha(z#))
            SetSpriteVisible(treeSpr[k], 1)
        endif
    next k

    // ---- Finish gate ----
    wy# = 0.0 - TRACK_LEN
    z# = playerY - wy#
    if z# < -150.0 or z# > ZFAR
        SetSpriteVisible(sprFinish, 0)
    else
        ProjectPt(wy#, 0.0, 0.0)
        w# = (ROAD_W + 80) * gS
        h# = 250.0 * gS
        SetSpriteSize(sprFinish, w#, h#)
        SetSpritePosition(sprFinish, gSX - w# * 0.5, gSY - h# * 0.97)
        SetSpriteDepth(sprFinish, DepthFor(wy#))
        SetSpriteColor(sprFinish, 255, 255, 255, FogAlpha(z#))
        SetSpriteVisible(sprFinish, 1)
    endif

    // ---- Flags and bonuses ----
    for i = 0 to MAX_ITEMS
        z# = playerY - items[i].y
        if items[i].got = 1 or z# < -150.0 or z# > ZFAR
            SetSpriteVisible(items[i].spr, 0)
        else
            lift# = 0.0
            if items[i].kind = 1 then lift# = 26.0       // bonus floats
            ProjectPt(items[i].y, items[i].lane * LANE_W, lift#)
            if items[i].kind = 0
                w# = 44.0 * gS
                h# = 76.0 * gS
            else
                w# = 46.0 * gS
                h# = 46.0 * gS
            endif
            SetSpriteSize(items[i].spr, w#, h#)
            SetSpritePosition(items[i].spr, gSX - w# * 0.5, gSY - h#)
            SetSpriteDepth(items[i].spr, DepthFor(items[i].y))
            SetSpriteColor(items[i].spr, 255, 255, 255, FogAlpha(z#))
            SetSpriteVisible(items[i].spr, 1)
        endif
    next i

    // ---- Enemies ----
    for i = 0 to MAX_ENEMIES
        z# = playerY - enemies[i].y
        if enemies[i].active = 0 or z# < -150.0 or z# > ZFAR
            SetSpriteVisible(enemies[i].spr, 0)
        else
            ProjectPt(enemies[i].y, enemies[i].lane * LANE_W, 0.0)
            w# = 96.0 * gS
            h# = 86.0 * gS
            if enemies[i].active = 2               // squashed
                w# = w# * 1.2
                h# = h# * 0.15
            endif
            SetSpriteSize(enemies[i].spr, w#, h#)
            SetSpritePosition(enemies[i].spr, gSX - w# * 0.5, gSY - h# * 0.9)
            SetSpriteDepth(enemies[i].spr, DepthFor(enemies[i].y))
            al = FogAlpha(z#)
            if enemies[i].active = 2
                SetSpriteColor(enemies[i].spr, 90, 25, 25, al)
            else
                SetSpriteColor(enemies[i].spr, 255, 255, 255, al)
            endif
            SetSpriteVisible(enemies[i].spr, 1)
        endif
    next i

    // ---- Player and shadow ----
    // In a jump the car is lifted into the air (lift); the shadow stays on the road and shrinks.
    ProjectPt(playerY, offX, 0.0)
    shd# = 1.0 / (1.0 + jump_height / 300.0)
    w# = 100.0 * shd# * gS
    h# = 30.0 * shd# * gS
    SetSpriteSize(sprShadow, w#, h#)
    SetSpritePosition(sprShadow, gSX - w# * 0.5, gSY - h# * 0.45)
    SetSpriteDepth(sprShadow, DepthFor(playerY) + 1)

    ProjectPt(playerY, offX, jump_height)
    w# = 96.0 * gS
    h# = 86.0 * gS
    SetSpriteSize(sprPlayer, w#, h#)
    SetSpritePosition(sprPlayer, gSX - w# * 0.5, gSY - h# * 0.9)
    SetSpriteDepth(sprPlayer, DepthFor(playerY))

    // blinking after respawn
    if invuln > 0 and mod(invuln, 8) < 4
        SetSpriteVisible(sprPlayer, 0)
    else
        SetSpriteVisible(sprPlayer, 1)
    endif

    // ---- Particles ----
    for i = 0 to MAX_PART
        if partLife[i] > 0
            ProjectPt(partWY[i], partX[i], partY[i])
            w# = 14.0 * gS
            if w# < 3.0 then w# = 3.0
            SetSpriteSize(partSpr[i], w#, w#)
            SetSpritePosition(partSpr[i], gSX - w# * 0.5, gSY - w# * 0.5)
        endif
    next i

    // ---- HUD ----
    SetTextString(txtScore, "SCORE: " + str(score))
    SetTextString(txtKeys, "Arrows / WASD: drive   Space / Z: jump   M: sound   [key: " + str(GetRawLastKey()) + "]")
    SetTextString(txtLives, "LIVES: " + str(lives))
    SetTextString(txtFlags, "FLAGS: " + str(flagsGot) + "/" + str(NUM_FLAGS))
    SetTextString(txtSpeed, "SPEED: " + str(speed * 12.0, 0) + " km/h")
    sl# = Slope(playerY)
    if sl# > 0.25
        SetTextString(txtSlope, "DOWNHILL")
    elseif sl# < -0.25
        SetTextString(txtSlope, "UPHILL")
    else
        SetTextString(txtSlope, "FLAT")
    endif

    if msgTimer > 0
        SetTextString(txtMsg, message$)
        SetTextVisible(txtMsg, 1)
    else
        SetTextVisible(txtMsg, 0)
    endif
endfunction

// =====================================================================
//  SOUND AND MUSIC  (procedural synthesis into memblocks)
//
//  Technique: the "Generate sounds with memblocks" idea by Ric / Phaelax.
//  Header of an AGK sound memblock (12 bytes):
//     bytes 0-1   number of channels (short)
//     bytes 2-3   bits per sample    (short)
//     bytes 4-7   sample rate        (int)
//     bytes 8-11  number of frames   (int)   -> followed by 16-bit mono data
//  In this implementation the phase is accumulated with a phase accumulator,
//  so pitch slides do not crackle.
// =====================================================================

function InitAudio()
    local i as integer

    // --- MIDI note -> frequency (A4 = note 69 = 440 Hz) ---
    noteFreq[69] = 440.0
    for i = 70 to 127
        noteFreq[i] = noteFreq[i - 1] * 1.0594631
    next i
    for i = 68 to 0 step -1
        noteFreq[i] = noteFreq[i + 1] / 1.0594631
    next i

    // Loading text (rendering the music takes a moment)
    SetTextString(txtMsg, "Loading sounds...")
    SetTextVisible(txtMsg, 1)
    Sync()

    // MakeTone(id, duration ms, wave, f start, f end, volume,
    //          decay(0/1/2), noise mix, noise filter, vibrato Hz, vibrato depth, attack ms)
    // wave: 0 = sine, 1 = square, 2 = triangle, 3 = 25 % pulse

    // Jump: rising "boing"
    MakeTone(SND_JUMP, 200, 1, 220.0, 640.0, 0.30, 1, 0.0, 1.0, 0.0, 0.0, 3)

    // Landing: thud (dark noise + low triangle)
    MakeTone(SND_LAND, 110, 2, 130.0, 55.0, 0.55, 2, 0.55, 0.25, 0.0, 0.0, 2)

    // Crash: long explosion (filtered noise + falling square)
    MakeTone(SND_CRASH, 700, 1, 110.0, 35.0, 0.85, 2, 0.85, 0.30, 0.0, 0.0, 2)

    // Squash: "splat" - quick falling tone + noise
    MakeTone(SND_SQUASH, 220, 1, 520.0, 70.0, 0.40, 2, 0.35, 0.6, 0.0, 0.0, 2)

    // Flag / bonus / respawn / win / game over: short note sequences
    MakeSequence(SND_FLAG,     "7684",             70, 3, 0.30)
    MakeSequence(SND_BONUS,    "72767984",         55, 1, 0.25)
    MakeSequence(SND_RESPAWN,  "55596267",         80, 2, 0.45)
    MakeSequence(SND_WIN,      "72767984798476",  120, 3, 0.32)
    MakeSequence(SND_GAMEOVER, "67646055",        240, 2, 0.50)

    // Engine: seamless loop. 105 Hz x 0.2 s = exactly 21 cycles.
    MakeTone(SND_ENGINE, 200, 3, 105.0, 105.0, 0.22, 0, 0.0, 1.0, 0.0, 0.0, 0)

    // Music (~6.4 s loop)
    BuildMusic(SND_MUSIC)

    // Start the engine at volume 0 (UpdateAudio adjusts it)
    engineInst = PlaySound(SND_ENGINE, 0, 1)
    muted = 0

    SetTextVisible(txtMsg, 0)
endfunction

// Waveform from phase ph (0..1) -> -1..1
function Osc(kind as integer, ph#)
    local v# as float
    if kind = 0
        v# = sin(ph# * 360.0)
    elseif kind = 1
        if ph# < 0.5
            v# = 1.0
        else
            v# = -1.0
        endif
    elseif kind = 2
        v# = 4.0 * abs(ph# - 0.5) - 1.0
    else
        if ph# < 0.25
            v# = 1.0
        else
            v# = -1.0
        endif
    endif
endfunction v#

// General-purpose effect generator
function MakeTone(id as integer, ms as integer, wave as integer, f0# as float, f1# as float, vol# as float, decayPow as integer, noiseMix# as float, noiseCoef# as float, vibHz# as float, vibDepth# as float, attackMs as integer)
    local frames as integer
    local mem as integer
    local i as integer
    local v as integer
    local atk as integer
    local ph# as float
    local t# as float
    local f# as float
    local s# as float
    local env# as float
    local nz# as float
    local nf# as float

    frames = ms * SAMPLE_RATE / 1000
    atk = attackMs * SAMPLE_RATE / 1000
    mem = CreateMemblock(12 + frames * 2)
    SetMemblockShort(mem, 0, 1)             // mono
    SetMemblockShort(mem, 2, 16)            // 16 bits
    SetMemblockInt(mem, 4, SAMPLE_RATE)
    SetMemblockInt(mem, 8, frames)

    ph# = 0.0
    nf# = 0.0
    for i = 0 to frames - 1
        t# = i * 1.0 / frames
        f# = f0# + (f1# - f0#) * t#
        if vibDepth# > 0.0
            f# = f# * (1.0 + vibDepth# * sin(vibHz# * i / SAMPLE_RATE * 360.0))
        endif
        ph# = ph# + f# / SAMPLE_RATE
        if ph# >= 1.0 then ph# = ph# - 1.0

        nz# = Random(0, 2000) / 1000.0 - 1.0
        nf# = nf# + (nz# - nf#) * noiseCoef#
        s# = Osc(wave, ph#) * (1.0 - noiseMix#) + nf# * noiseMix#

        if decayPow = 0
            env# = 1.0
        else
            env# = 1.0 - t#
            if decayPow = 2 then env# = env# * env#
        endif
        if i < atk then env# = env# * i / atk

        v = Trunc(s# * env# * vol# * 32000.0)
        if v > 32000 then v = 32000
        if v < -32000 then v = -32000
        SetMemblockShort(mem, 12 + i * 2, v)
    next i

    if GetSoundExists(id) = 1 then DeleteSound(id)
    CreateSoundFromMemblock(id, mem)
    DeleteMemblock(mem)
endfunction

// Note sequence: notes$ = two-digit MIDI notes ("00" = rest)
function MakeSequence(id as integer, notes$ as string, stepMs as integer, wave as integer, vol# as float)
    local n as integer
    local stepFrames as integer
    local frames as integer
    local mem as integer
    local k as integer
    local j as integer
    local note as integer
    local v as integer
    local f# as float
    local ph# as float
    local e# as float
    local s# as float

    n = Len(notes$) / 2
    stepFrames = stepMs * SAMPLE_RATE / 1000
    frames = n * stepFrames
    mem = CreateMemblock(12 + frames * 2)
    SetMemblockShort(mem, 0, 1)
    SetMemblockShort(mem, 2, 16)
    SetMemblockInt(mem, 4, SAMPLE_RATE)
    SetMemblockInt(mem, 8, frames)

    ph# = 0.0
    for k = 0 to n - 1
        note = Val(Mid(notes$, k * 2 + 1, 2))
        f# = 0.0
        if note > 0 then f# = noteFreq[note]
        for j = 0 to stepFrames - 1
            ph# = ph# + f# / SAMPLE_RATE
            if ph# >= 1.0 then ph# = ph# - 1.0
            e# = 1.0 - 0.5 * j / stepFrames
            if j < 40 then e# = e# * j / 40.0
            if j > stepFrames - 40 then e# = e# * (stepFrames - j) / 40.0
            s# = 0.0
            if f# > 0.0 then s# = Osc(wave, ph#) * e# * vol#
            v = Trunc(s# * 32000.0)
            SetMemblockShort(mem, 12 + (k * stepFrames + j) * 2, v)
        next j
    next k

    if GetSoundExists(id) = 1 then DeleteSound(id)
    CreateSoundFromMemblock(id, mem)
    DeleteMemblock(mem)
endfunction

// Chiptune music: lead (25 % pulse) + bass (triangle) + drums (noise)
// 32 eighth notes, 150 BPM -> 6.4 s. Chord progression Am - F - C - G.
function BuildMusic(id as integer)
    local stepFrames as integer
    local steps as integer
    local frames as integer
    local mem as integer
    local s as integer
    local j as integer
    local bar as integer
    local b as integer
    local ln as integer
    local bn as integer
    local root as integer
    local v as integer
    local isKick as integer
    local isSnare as integer
    local isHat as integer
    local lead$ as string
    local lf# as float
    local bf# as float
    local lph# as float
    local bph# as float
    local kph# as float
    local g# as float
    local l# as float
    local bs# as float
    local d# as float
    local kt# as float
    local m# as float

    stepFrames = SAMPLE_RATE / 5       // 200 ms
    steps = 32
    frames = steps * stepFrames

    lead$ = "6900720076726900" + "6500690072696500" + "6700720076726700" + "6771747167006200"

    mem = CreateMemblock(12 + frames * 2)
    SetMemblockShort(mem, 0, 1)
    SetMemblockShort(mem, 2, 16)
    SetMemblockInt(mem, 4, SAMPLE_RATE)
    SetMemblockInt(mem, 8, frames)

    lph# = 0.0
    bph# = 0.0
    kph# = 0.0

    for s = 0 to steps - 1
        bar = s / 8
        b = mod(s, 8)
        if bar = 0 then root = 45
        if bar = 1 then root = 41
        if bar = 2 then root = 48
        if bar = 3 then root = 43
        bn = root
        if b = 2 or b = 6 then bn = root + 12

        ln = Val(Mid(lead$, s * 2 + 1, 2))
        lf# = 0.0
        if ln > 0 then lf# = noteFreq[ln]
        bf# = noteFreq[bn]

        isKick = 0
        isSnare = 0
        isHat = 0
        if mod(s, 4) = 0 then isKick = 1
        if mod(s, 4) = 2 then isSnare = 1
        if mod(s, 2) = 1 then isHat = 1

        kph# = 0.0
        for j = 0 to stepFrames - 1
            // soft start/end to avoid clicks
            g# = 1.0
            if j < 40 then g# = j / 40.0
            if j > stepFrames - 60 then g# = (stepFrames - j) / 60.0

            // lead
            l# = 0.0
            if lf# > 0.0
                lph# = lph# + lf# / SAMPLE_RATE
                if lph# >= 1.0 then lph# = lph# - 1.0
                if lph# < 0.25
                    l# = 1.0
                else
                    l# = -1.0
                endif
                l# = l# * 0.20 * (1.0 - 0.5 * j / stepFrames) * g#
            endif

            // bass
            bph# = bph# + bf# / SAMPLE_RATE
            if bph# >= 1.0 then bph# = bph# - 1.0
            bs# = (4.0 * abs(bph# - 0.5) - 1.0) * 0.30 * (1.0 - 0.6 * j / stepFrames) * g#

            // drums
            d# = 0.0
            if isKick = 1 and j < 2600
                kt# = j / 2600.0
                kph# = kph# + (140.0 - 100.0 * kt#) / SAMPLE_RATE
                d# = d# + sin(kph# * 360.0) * (1.0 - kt#) * 0.45
            endif
            if isSnare = 1 and j < 2200
                d# = d# + (Random(0, 2000) / 1000.0 - 1.0) * (1.0 - j / 2200.0) * 0.22
            endif
            if isHat = 1 and j < 900
                d# = d# + (Random(0, 2000) / 1000.0 - 1.0) * (1.0 - j / 900.0) * 0.10
            endif

            m# = l# + bs# + d#
            v = Trunc(m# * 30000.0)
            if v > 32000 then v = 32000
            if v < -32000 then v = -32000
            SetMemblockShort(mem, 12 + (s * stepFrames + j) * 2, v)
        next j
    next s

    if GetSoundExists(id) = 1 then DeleteSound(id)
    CreateSoundFromMemblock(id, mem)
    DeleteMemblock(mem)
endfunction

// =====================================================================
//  AUDIO CONTROL DURING THE GAME
// =====================================================================
function StartMusic()
    StopSound(SND_MUSIC)
    StopSound(SND_WIN)
    StopSound(SND_GAMEOVER)
    PlaySound(SND_MUSIC, 40, 1)        // 1 = loop
endfunction

// Engine sound: pitch and volume follow speed, M = mute
function UpdateAudio()
    local rate# as float
    local minR# as float
    local maxR# as float
    local vol as integer

    if GetRawKeyPressed(77) = 1
        muted = 1 - muted
        if muted = 1
            SetSoundSystemVolume(0)
        else
            SetSoundSystemVolume(100)
        endif
    endif

    if gameState = GAME_PLAY and playerState <> STATE_CRASHED
        if GetSoundInstancePlaying(engineInst) = 0
            engineInst = PlaySound(SND_ENGINE, 0, 1)
        endif

        rate# = 0.6 + speed / 16.0 * 1.4          // 0.6 ... 2.0
        minR# = GetSoundMinRate()
        maxR# = GetSoundMaxRate()
        if rate# < minR# then rate# = minR#
        if rate# > maxR# then rate# = maxR#
        SetSoundInstanceRate(engineInst, rate#)

        vol = 10 + speed * 1.5
        if is_jumping = 1 then vol = vol / 3      // the engine quietens in the air
        SetSoundInstanceVolume(engineInst, vol)
    else
        if GetSoundInstancePlaying(engineInst) = 1
            SetSoundInstanceVolume(engineInst, 0)
        endif
    endif
endfunction


// =====================================================================
//  PSEUDO-3D: PROJECTION, HEIGHT, DEPTH
// =====================================================================

// Terrain height at world Y. Consistent with the Slope() function:
// when Slope > 0 (downhill), the height decreases in the driving direction (Y decreases).
function ElevAt(y#)
    e# = 0.0 - HILL_AMP * cos(y# * 0.30)
endfunction e#

// Projects a world point (wy = distance along the track, lat = lateral offset
// from the road centre, lift = height above the road) to screen coordinates.
// Result goes into the globals: gSX, gSY (screen) and gS (perspective scale).
function ProjectPt(wy# as float, lat# as float, lift# as float)
    local z# as float
    local s# as float
    local rel# as float
    local curve# as float
    z# = playerY - wy#
    if z# < -165.0 then z# = -165.0
    s# = PERSP_F / (PERSP_F + z#)
    rel# = ElevAt(wy#) - playerElev
    curve# = (RoadCenter(wy#) - roadCP) * CURVE_K
    gS  = s#
    gSX = 360.0 + (curve# + lat# - camLat) * s#
    gSY = HORIZON_Y + (PLAYER_SY - HORIZON_Y) * s# - (rel# * HILL_K + lift#) * s#
endfunction

// Draw order: the nearer object (smaller z) covers the farther one.
function DepthFor(wy# as float)
    local idx as integer
    local d as integer
    idx = Floor((wy# - rowBase * SEG) / SEG)
    d = 6000 - idx * 10 - 5
    if d < 100 then d = 100
    if d > 8900 then d = 8900
endfunction d

// Fog: distant objects fade out
function FogAlpha(z# as float)
    local f# as float
    local a as integer
    f# = z# / ZFAR
    if f# < 0.0 then f# = 0.0
    if f# > 1.0 then f# = 1.0
    a = 255.0 * (1.0 - f# * f#)
endfunction a

// Row colour: slope shading + fog towards the horizon colour
function SetRowColor(spr as integer, r as integer, g as integer, b as integer, shade# as float, f# as float)
    local cr as integer
    local cg as integer
    local cb as integer
    cr = (r * shade#) * (1.0 - f#) + HAZE_R * f#
    cg = (g * shade#) * (1.0 - f#) + HAZE_G * f#
    cb = (b * shade#) * (1.0 - f#) + HAZE_B * f#
    if cr < 0 then cr = 0
    if cg < 0 then cg = 0
    if cb < 0 then cb = 0
    if cr > 255 then cr = 255
    if cg > 255 then cg = 255
    if cb > 255 then cb = 255
    SetSpriteColor(spr, cr, cg, cb, 255)
endfunction

// =====================================================================
//  DRAWING IMAGES INTO MEMBLOCKS (no external image files)
//  Image memblock: width, height, bits (32) + RGBA pixels
// =====================================================================
function BeginImg(w as integer, h as integer)
    local i as integer
    imgW = w
    imgH = h
    imgMem = CreateMemblock(12 + w * h * 4)
    SetMemblockInt(imgMem, 0, w)
    SetMemblockInt(imgMem, 4, h)
    SetMemblockInt(imgMem, 8, 32)
    for i = 0 to w * h - 1
        SetMemblockInt(imgMem, 12 + i * 4, 0)       // transparent
    next i
endfunction

function EndImg(id as integer)
    CreateImageFromMemblock(id, imgMem)
    DeleteMemblock(imgMem)
endfunction

function ImgClamp(v# as float)
    local c as integer
    c = Trunc(v#)
    if c < 0 then c = 0
    if c > 255 then c = 255
endfunction c

function ImgPut(x as integer, y as integer, r as integer, g as integer, b as integer, a as integer)
    local o as integer
    if x < 0 or y < 0 or x >= imgW or y >= imgH then exitfunction
    o = 12 + (y * imgW + x) * 4
    SetMemblockByte(imgMem, o,     r)
    SetMemblockByte(imgMem, o + 1, g)
    SetMemblockByte(imgMem, o + 2, b)
    SetMemblockByte(imgMem, o + 3, a)
endfunction

function ImgFill(x1 as integer, y1 as integer, x2 as integer, y2 as integer, r as integer, g as integer, b as integer, a as integer)
    local x as integer
    local y as integer
    for y = y1 to y2
        for x = x1 to x2
            ImgPut(x, y, r, g, b, a)
        next x
    next y
endfunction

// Rectangle with vertical shading (k1 at the top, k2 at the bottom)
function ImgShade(x1 as integer, y1 as integer, x2 as integer, y2 as integer, r as integer, g as integer, b as integer, k1# as float, k2# as float)
    local x as integer
    local y as integer
    local t# as float
    local k# as float
    for y = y1 to y2
        t# = 0.0
        if y2 > y1 then t# = (y - y1) * 1.0 / (y2 - y1)
        k# = k1# + (k2# - k1#) * t#
        for x = x1 to x2
            ImgPut(x, y, ImgClamp(r * k#), ImgClamp(g * k#), ImgClamp(b * k#), 255)
        next x
    next y
endfunction

// Trapezoid: left/right edges are interpolated between the top and bottom rows
function ImgTrap(yTop as integer, yBot as integer, xl1 as integer, xr1 as integer, xl2 as integer, xr2 as integer, r as integer, g as integer, b as integer, k1# as float, k2# as float)
    local x as integer
    local y as integer
    local xa as integer
    local xb as integer
    local t# as float
    local k# as float
    for y = yTop to yBot
        t# = (y - yTop) * 1.0 / (yBot - yTop)
        xa = Trunc(xl1 + (xl2 - xl1) * t#)
        xb = Trunc(xr1 + (xr2 - xr1) * t#)
        k# = k1# + (k2# - k1#) * t#
        for x = xa to xb
            ImgPut(x, y, ImgClamp(r * k#), ImgClamp(g * k#), ImgClamp(b * k#), 255)
        next x
    next y
endfunction

// Car seen from behind/above: wheels, rear wall + tail lights + bumper,
// trunk, rear window and roof.  Image 80 x 72 px.
function MakeCarImage(id as integer, r as integer, g as integer, b as integer)
    BeginImg(80, 72)

    ImgFill(8, 63, 72, 69, 0, 0, 0, 90)                  // shadow on the ground

    ImgFill(3, 38, 14, 65, 24, 24, 28, 255)              // wheels
    ImgFill(66, 38, 77, 65, 24, 24, 28, 255)
    ImgFill(5, 40, 6, 63, 75, 75, 84, 255)               // wheel highlight
    ImgFill(68, 40, 69, 63, 75, 75, 84, 255)

    ImgShade(9, 36, 70, 62, r, g, b, 0.95, 0.60)         // rear wall
    ImgFill(9, 36, 70, 37, ImgClamp(r * 1.35), ImgClamp(g * 1.35), ImgClamp(b * 1.35), 255)
    ImgFill(8, 58, 71, 63, ImgClamp(r * 0.30), ImgClamp(g * 0.30), ImgClamp(b * 0.30), 255)   // bumper
    ImgFill(11, 59, 68, 59, 205, 205, 210, 255)          // chrome trim

    ImgFill(11, 41, 24, 50, 110, 10, 10, 255)            // tail lights
    ImgFill(12, 42, 23, 49, 255, 50, 40, 255)
    ImgFill(14, 43, 21, 46, 255, 210, 170, 255)
    ImgFill(55, 41, 68, 50, 110, 10, 10, 255)
    ImgFill(56, 42, 67, 49, 255, 50, 40, 255)
    ImgFill(58, 43, 65, 46, 255, 210, 170, 255)

    ImgFill(33, 47, 46, 55, 40, 40, 40, 255)             // licence plate
    ImgFill(34, 48, 45, 54, 235, 235, 225, 255)

    ImgTrap(22, 35, 14, 65, 9, 70, r, g, b, 1.25, 1.05)  // trunk
    ImgTrap(11, 21, 23, 56, 17, 62, 30, 45, 72, 1.0, 0.8)   // rear window
    ImgFill(26, 13, 35, 14, 125, 155, 195, 255)          // window reflection
    ImgTrap(5, 10, 27, 52, 23, 56, r, g, b, 1.45, 1.30)  // roof

    ImgFill(10, 24, 13, 28, ImgClamp(r * 0.8), ImgClamp(g * 0.8), ImgClamp(b * 0.8), 255)   // mirrors
    ImgFill(66, 24, 69, 28, ImgClamp(r * 0.8), ImgClamp(g * 0.8), ImgClamp(b * 0.8), 255)

    EndImg(id)
endfunction

// Soft elliptical shadow 96 x 28
function MakeShadowImage(id as integer)
    local x as integer
    local y as integer
    local nx# as float
    local ny# as float
    local d# as float
    BeginImg(96, 28)
    for y = 0 to 27
        for x = 0 to 95
            nx# = (x - 47.5) / 48.0
            ny# = (y - 13.5) / 14.0
            d# = nx# * nx# + ny# * ny#
            if d# < 1.0 then ImgPut(x, y, 0, 0, 0, Trunc(150.0 * (1.0 - d#)))
        next x
    next y
    EndImg(id)
endfunction

// Flag: pole + pennant 36 x 64
function MakeFlagImage(id as integer)
    local x as integer
    local y as integer
    local wd# as float
    BeginImg(36, 64)
    ImgFill(12, 58, 22, 63, 60, 60, 66, 255)
    ImgFill(16, 2, 18, 62, 195, 195, 200, 255)
    for y = 4 to 24
        wd# = 15.0 - abs(y - 14) * 1.4
        for x = 19 to 19 + Trunc(wd#)
            ImgPut(x, y, 255, ImgClamp(215 - (y - 4) * 4), 20, 255)
        next x
    next y
    EndImg(id)
endfunction

// Coin 40 x 40
function MakeCoinImage(id as integer)
    local x as integer
    local y as integer
    local dx# as float
    local dy# as float
    local d# as float
    BeginImg(40, 40)
    for y = 0 to 39
        for x = 0 to 39
            dx# = x - 19.5
            dy# = y - 19.5
            d# = sqrt(dx# * dx# + dy# * dy#)
            if d# <= 18.0
                if d# > 14.5
                    ImgPut(x, y, 175, 120, 10, 255)
                elseif d# > 9.0 and d# < 11.0
                    ImgPut(x, y, 235, 175, 20, 255)
                else
                    ImgPut(x, y, 255, ImgClamp(215 + dy# * 2.0), 45, 255)
                endif
            endif
        next x
    next y
    ImgFill(17, 12, 22, 27, 235, 175, 20, 255)           // coin emblem
    EndImg(id)
endfunction

// Finish gate 128 x 96: checkered beam + posts
function MakeGateImage(id as integer)
    local x as integer
    local y as integer
    local cx as integer
    local cy as integer
    BeginImg(128, 96)
    ImgFill(0, 12, 7, 95, 200, 200, 205, 255)
    ImgFill(120, 12, 127, 95, 200, 200, 205, 255)
    ImgFill(0, 12, 2, 95, 235, 235, 240, 255)
    ImgFill(120, 12, 122, 95, 235, 235, 240, 255)
    for y = 0 to 17
        for x = 0 to 127
            cx = x / 8
            cy = y / 6
            if mod(cx + cy, 2) = 0
                ImgPut(x, y, 245, 245, 245, 255)
            else
                ImgPut(x, y, 20, 20, 20, 255)
            endif
        next x
    next y
    EndImg(id)
endfunction

function MakeParticleImage(id as integer)
    local x as integer
    local y as integer
    BeginImg(12, 12)
    for y = 0 to 11
        for x = 0 to 11
            if (x - 5.5) * (x - 5.5) + (y - 5.5) * (y - 5.5) <= 30.0 then ImgPut(x, y, 255, 255, 255, 255)
        next x
    next y
    EndImg(id)
endfunction

// Tree 64 x 96
function MakeTreeImage(id as integer)
    local x as integer
    local y as integer
    local v# as float
    local inside as integer
    BeginImg(64, 96)
    ImgFill(28, 58, 36, 95, 100, 65, 30, 255)
    ImgFill(28, 58, 31, 95, 135, 90, 42, 255)
    for y = 0 to 72
        for x = 0 to 63
            inside = 0
            if (x - 32) * (x - 32) + (y - 30) * (y - 30) <= 784 then inside = 1
            if (x - 18) * (x - 18) + (y - 48) * (y - 48) <= 324 then inside = 1
            if (x - 46) * (x - 46) + (y - 48) * (y - 48) <= 324 then inside = 1
            if inside = 1
                v# = 0.60 + 0.55 * (1.0 - y / 72.0)
                if x < 28 then v# = v# + 0.10
                ImgPut(x, y, ImgClamp(28 * v#), ImgClamp(125 * v#), ImgClamp(38 * v#), 255)
            endif
        next x
    next y
    EndImg(id)
endfunction

// Distant mountains 360 x 40 (stretched to the screen width)
function MakeMountainImage(id as integer)
    local x as integer
    local y as integer
    local top as integer
    local t# as float
    BeginImg(360, 40)
    for x = 0 to 359
        top = Trunc(20.0 + 9.0 * sin(x * 2.0) + 6.0 * sin(x * 5.3 + 30.0) + 4.0 * sin(x * 0.7))
        if top < 3 then top = 3
        if top > 36 then top = 36
        for y = top to 39
            t# = (y - top) * 1.0 / (40 - top)
            ImgPut(x, y, ImgClamp(88.0 + (HAZE_R - 88.0) * t#), ImgClamp(122.0 + (HAZE_G - 122.0) * t#), ImgClamp(158.0 + (HAZE_B - 158.0) * t#), 255)
        next y
    next x
    EndImg(id)
endfunction


// =====================================================================
//  KEYBOARD: arrow keys AND WASD both work (and Z as a jump alternative)
//  Codes: arrows 37 left, 38 up, 39 right, 40 down
//          A = 65, D = 68, S = 83, W = 87, Space = 32, Z = 90
// =====================================================================
function KeyUp()
    local r as integer
    r = 0
    if GetRawKeyState(38) = 1 or GetRawKeyState(87) = 1 then r = 1
endfunction r

function KeyDown()
    local r as integer
    r = 0
    if GetRawKeyState(40) = 1 or GetRawKeyState(83) = 1 then r = 1
endfunction r

function KeyLeftPressed()
    local r as integer
    r = 0
    if GetRawKeyPressed(37) = 1 or GetRawKeyPressed(65) = 1 then r = 1
endfunction r

function KeyRightPressed()
    local r as integer
    r = 0
    if GetRawKeyPressed(39) = 1 or GetRawKeyPressed(68) = 1 then r = 1
endfunction r

function KeyJumpPressed()
    local r as integer
    r = 0
    if GetRawKeyPressed(32) = 1 or GetRawKeyPressed(90) = 1 then r = 1
endfunction r


// Enemy spawn position: far ahead, at least 500 px from other cars
function FindSpawnY(i as integer)
    local j as integer
    local tries as integer
    local ok as integer
    local cand# as float
    tries = 0
    ok = 0
    cand# = playerY - 2400.0
    while ok = 0 and tries < 10
        cand# = playerY - 1800.0 - Random(0, 2200)
        ok = 1
        for j = 0 to MAX_ENEMIES
            if j <> i and enemies[j].active = 1
                if abs(enemies[j].y - cand#) < 500.0 then ok = 0
            endif
        next j
        tries = tries + 1
    endwhile
endfunction cand#
