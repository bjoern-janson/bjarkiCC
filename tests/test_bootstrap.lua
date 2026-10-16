local ns = {}
local healthOffsets={player={24,24},target={-24,24},focus={-24,24}}
local path = (ADDON_DIR or 'work/bjarkiCC') .. '/Bootstrap.lua'
local file = io.open(path)
assert(file, 'Bootstrap is not implemented yet')
file:close()
local secret = {}
issecretvalue = function(v) return v == secret end
issecrettable = function(v) return false end
canaccessvalue = function(v) return v ~= secret end
assert(loadfile(path))('bjarkiCC', ns)
assert(not ns.Safe.Readable(secret), 'secret values must be rejected')
assert(ns.Safe.Number(secret) == nil, 'no number from secret')
assert(ns.Safe.Number(0/0) == nil, 'NaN must be rejected')
assert(ns.Safe.Number(math.huge) == nil, 'infinity must be rejected')
assert(ns.Safe.Call(function() error('blocked') end) == nil, 'failed API unavailable')
assert(ns.Safe.Call(function() return false end) == false, 'false is a readable value')
assert(ns.Safe.Call(function() return secret end) == nil, 'secret API result unavailable')
ns.Data = {categories={{key='stun'},{key='fear'}}}
bjarkiCCDB = {bars={player={size=999,gap=-1,x='bad',vertical=true}},resetSeconds=0,
    cooldownOverrides={[853]=-10,[408]=30},locked='yes',targetOnly=true,categories={stun=false}}
ns.InitializeDB()
assert(ns.db.bars.player.size <= 72 and ns.db.bars.player.gap >= 0, 'saved layout bounded')
assert(type(ns.db.bars.player.x) == 'number', 'malformed saved position recovered')
assert(ns.db.bars.player.vertical == true and ns.db.targetOnly, 'valid preferences retained')
assert(ns.db.categories.stun == false and ns.db.categories.fear == true, 'category defaults merged')
assert(ns.db.resetSeconds >= 10 and ns.db.locked == true, 'malformed defaults recovered')
assert(ns.db.cooldownOverrides[853] == nil and ns.db.cooldownOverrides[408] == 30, 'overrides sanitized')
ns.db.bars.player.x = 300
ns.ResetPositions()
assert(ns.db.bars.player.x == -230 and ns.db.bars.player.vertical == true, 'reset only placement')

-- Loading without saved settings produces the compact, icon-only layout.
bjarkiCCDB = nil
ns.InitializeDB()
assert(ns.db.bars.player.size == 28 and ns.db.bars.target.size == 28, 'fresh DR bars use compact icons')
assert(ns.db.bars.focus, 'fresh settings include a focus DR bar')
assert(ns.db.bars.focus.size == 28 and ns.db.bars.focus.x == 230 and ns.db.bars.focus.y == -230, 'focus gets compact icons and its fallback placement')
assert(ns.db.bars.cooldown.size == 32, 'fresh cooldown bar uses compact icons')
assert(ns.db.showNames == false and ns.db.showDRText == false, 'fresh bars omit optional text')
for _, key in ipairs({'player', 'target', 'focus', 'cooldown'}) do
    assert(ns.db.bars[key].gap == 3 and ns.db.bars[key].label == false, 'fresh bars have tight gaps and no labels')
end
for _, key in ipairs({'player', 'target', 'focus'}) do
    assert(ns.db.bars[key].anchorKind == 'health' and ns.db.bars[key].offsetX == healthOffsets[key][1] and ns.db.bars[key].offsetY == 24, 'fresh DR bars get inset health-bar offsets')
end
assert(ns.db.bars.cooldown.offsetX == nil and ns.db.bars.cooldown.offsetY == nil, 'cooldowns retain free placement')

-- The upgrade changes only previous visual defaults, preserving tracking and layout choices.
for _, oldSchema in ipairs({false, 0, 1}) do
    bjarkiCCDB = {
        schema=oldSchema or nil, locked=false, targetOnly=true, interrupts=true, resetSeconds=24,
        showNames=true, showDRText=true, categories={stun=false},
        disabledSpells={[853]=true}, cooldownOverrides={[408]=45},
        bars={
            player={size=36,gap=8,label=true,x=111,y=-222,enabled=false,vertical=true,reverse=true,maxIcons=7},
            target={size=44,gap=5,label=false,x=333,y=-444,enabled=true,vertical=false,reverse=false,maxIcons=9},
            cooldown={size=40,gap=8,label=true,x=555,y=-666,enabled=true,vertical=true,reverse=true,maxIcons=11},
        },
    }
    ns.InitializeDB()
    assert(ns.db.schema == 5, 'migration records the new schema')
    assert(ns.db.bars.player.size == 28 and ns.db.bars.cooldown.size == 32, 'previous default sizes migrate')
    assert(ns.db.bars.player.gap == 3 and ns.db.bars.cooldown.gap == 3, 'previous default gaps migrate')
    assert(ns.db.bars.player.label == false and ns.db.bars.cooldown.label == false, 'previous labels migrate off')
    assert(ns.db.bars.target.size == 44 and ns.db.bars.target.gap == 5, 'custom size and gap survive migration')
    for _, fixture in ipairs({{'player',111,-222,false,true,true,7},{'target',333,-444,true,false,false,9},{'cooldown',555,-666,true,true,true,11}}) do
        local bar = ns.db.bars[fixture[1]]
        assert(bar.x == fixture[2] and bar.y == fixture[3], 'saved positions survive migration')
        assert(bar.enabled == fixture[4] and bar.vertical == fixture[5] and bar.maxIcons == fixture[7], 'saved bar behavior survives migration')
        local expectedReverse = fixture[1] == 'cooldown' and fixture[6] or fixture[1] ~= 'player'
        assert(bar.reverse == expectedReverse, 'new unit placements adopt mirrored growth; cooldowns retain their direction')
    end
    assert(not ns.db.locked and ns.db.targetOnly and ns.db.interrupts and ns.db.resetSeconds == 24, 'tracking and timing preferences survive migration')
    assert(not ns.db.categories.stun and ns.db.disabledSpells[853] and ns.db.cooldownOverrides[408] == 45, 'ability preferences survive migration')
    assert(ns.db.showNames and ns.db.showDRText, 'explicit optional text preferences survive initialization')

    -- A deliberate choice matching an old default must stay selected on later reloads.
    ns.db.bars.player.size, ns.db.bars.target.size, ns.db.bars.cooldown.size = 36, 36, 40
    for _, key in ipairs({'player', 'target', 'cooldown'}) do ns.db.bars[key].gap = 8 end
    ns.InitializeDB()
    assert(ns.db.bars.player.size == 36 and ns.db.bars.target.size == 36 and ns.db.bars.cooldown.size == 40, 'migration runs only once for sizes')
    for _, key in ipairs({'player', 'target', 'cooldown'}) do
        assert(ns.db.bars[key].gap == 8, 'migration runs only once for gaps')
    end
end

-- Schema 2 absolute positions remain fallbacks and cannot become unit-frame offsets.
bjarkiCCDB = {
    schema=2, locked=false, targetOnly=true, showNames=true,
    bars={
        player={size=36,gap=8,label=true,x=111,y=-222,offsetX=111,offsetY=-222,vertical=true},
        target={size=44,gap=5,label=true,x=333,y=-444,offsetX=333,offsetY=-444,reverse=true},
        focus={x=777,y=-888,offsetX=777,offsetY=-888,enabled=false},
        cooldown={size=40,gap=8,label=true,x=555,y=-666},
    },
}
ns.InitializeDB()
assert(ns.db.schema == 5, 'schema 2 upgrades to health-anchored DR configuration')
for _, fixture in ipairs({{'player',111,-222},{'target',333,-444},{'focus',777,-888}}) do
    local bar = ns.db.bars[fixture[1]]
    assert(bar.x == fixture[2] and bar.y == fixture[3], 'schema 2 absolute positions remain fallbacks')
    assert(bar.anchorKind == 'health' and bar.offsetX == healthOffsets[fixture[1]][1] and bar.offsetY == 24, 'schema 2 always initializes health offsets independently')
end
assert(ns.db.bars.player.size == 36 and ns.db.bars.player.gap == 8 and ns.db.bars.player.label, 'schema 2 does not rerun visual migration')
assert(ns.db.bars.cooldown.x == 555 and ns.db.bars.cooldown.y == -666 and ns.db.bars.cooldown.size == 40 and ns.db.bars.cooldown.gap == 8 and ns.db.bars.cooldown.label, 'schema 2 cooldown placement and visuals survive')
assert(ns.db.bars.focus.size == 28 and ns.db.bars.focus.gap == 3 and not ns.db.bars.focus.enabled, 'focus fills missing defaults without discarding preferences')

-- Later reloads preserve deliberate relative offsets and all fallback coordinates.
for _, fixture in ipairs({{'player',0,0},{'target',15.5,-21.25},{'focus',-10000,10000}}) do
    local bar = ns.db.bars[fixture[1]]
    bar.offsetX, bar.offsetY = fixture[2], fixture[3]
end
for _ = 1, 2 do
    ns.InitializeDB()
    for _, fixture in ipairs({{'player',0,0,111,-222},{'target',15.5,-21.25,333,-444},{'focus',-10000,10000,777,-888}}) do
        local bar = ns.db.bars[fixture[1]]
        assert(bar.offsetX == fixture[2] and bar.offsetY == fixture[3], 'schema 5 reload preserves saved numeric offsets')
        assert(bar.x == fixture[4] and bar.y == fixture[5], 'schema 5 reload preserves fallback coordinates')
    end
end

ns.ResetPositions()
for _, fixture in ipairs({{'player',-230,-165},{'target',230,-165},{'focus',230,-230},{'cooldown',0,-280}}) do
    local bar = ns.db.bars[fixture[1]]
    assert(bar.x == fixture[2] and bar.y == fixture[3], 'position reset restores all fallback placements')
end
for _, key in ipairs({'player', 'target', 'focus'}) do
    assert(ns.db.bars[key].anchorKind == 'health' and ns.db.bars[key].offsetX == healthOffsets[key][1] and ns.db.bars[key].offsetY == 24, 'position reset restores health offsets')
end
assert(ns.db.bars.player.vertical and ns.db.bars.target.reverse and not ns.db.bars.focus.enabled, 'position reset preserves bar behavior')
assert(ns.db.bars.player.size == 36 and ns.db.bars.player.gap == 8 and ns.db.bars.player.label and not ns.db.locked and ns.db.targetOnly and ns.db.showNames, 'position reset preserves visual and tracking preferences')
assert(ns.db.bars.cooldown.offsetX == nil and ns.db.bars.cooldown.offsetY == nil, 'position reset keeps cooldowns freely placed')

-- Malformed saved offsets fall back while finite outliers clamp to the supported range.
bjarkiCCDB = {schema=3,bars={
    player={offsetX='bad',offsetY=0/0},
    target={offsetX=math.huge,offsetY=-math.huge},
    focus={offsetX=20001,offsetY=-20001},
}}
ns.InitializeDB()
assert(ns.db.bars.player.offsetX == 24 and ns.db.bars.player.offsetY == 24, 'invalid and NaN offsets use health defaults')
assert(ns.db.bars.target.offsetX == -24 and ns.db.bars.target.offsetY == 24, 'infinite offsets use health defaults')
assert(ns.db.bars.focus.offsetX == 10000 and ns.db.bars.focus.offsetY == -10000, 'finite offsets are bounded')
ns.db.bars.player.offsetX, ns.db.bars.player.offsetY = secret, false
ns.InitializeDB()
assert(ns.db.bars.player.offsetX == 24 and ns.db.bars.player.offsetY == 24, 'unreadable and nonnumeric offsets use health defaults')
-- v0.3.0 default offsets move closer; manual placements retain their old basis.
bjarkiCCDB={schema=3,bars={
    player={offsetX=6,offsetY=-8},
    target={offsetX=19,offsetY=-33},
    focus={offsetX=-55,offsetY=12},
    cooldown={x=444,y=-333},
}}
ns.InitializeDB()
assert(ns.db.bars.player.anchorKind=='health' and ns.db.bars.player.offsetX==24 and ns.db.bars.player.offsetY==24,'schema 3 defaults migrate to health geometry')
assert(ns.db.bars.target.anchorKind=='frame' and ns.db.bars.target.offsetX==19 and ns.db.bars.target.offsetY==-33,'custom target placement keeps its old frame basis')
assert(ns.db.bars.focus.anchorKind=='frame' and ns.db.bars.focus.offsetX==-55 and ns.db.bars.focus.offsetY==12,'custom focus placement keeps its old frame basis')
assert(ns.db.bars.cooldown.x==444 and ns.db.bars.cooldown.y==-333,'portrait upgrade leaves cooldown placement intact')
ns.InitializeDB()
assert(ns.db.bars.target.anchorKind=='frame' and ns.db.bars.target.offsetX==19,'custom legacy placement survives reload')
ns.ResetPositions()
assert(ns.db.bars.target.anchorKind=='health' and ns.db.bars.target.offsetX==-24 and ns.db.bars.target.offsetY==24,'reset opts legacy custom positions into the new health geometry')
-- Fresh layouts use inward-facing rows above the visible health bars.
bjarkiCCDB=nil
ns.InitializeDB()
assert(ns.db.schema==5,'health-bar layout records schema 5')
assert(ns.db.ownCastEstimates==true,'own-cast estimates are enabled by default')
for _,key in ipairs({'player','target','focus'}) do
    local bar=ns.db.bars[key]
    assert(bar.anchorKind=='health' and bar.offsetX==healthOffsets[key][1] and bar.offsetY==24,'fresh DR rows align above the health bar with room for leader badges')
    assert(bar.reverse==(key~='player'),'default rows grow inward from the portrait side')
end
ns.db.ownCastEstimates=false
ns.InitializeDB()
assert(ns.db.ownCastEstimates==false,'explicitly disabled own-cast estimates survive reload')
-- Only former default placements migrate; custom portrait/frame geometry and
-- growth directions are meaningful user choices in their old coordinate basis.
bjarkiCCDB={schema=4,bars={
    player={anchorKind='portrait',offsetX=0,offsetY=8,reverse=true},
    target={anchorKind='portrait',offsetX=10,offsetY=0,reverse=false},
    focus={anchorKind='portrait',offsetX=-7,offsetY=31,reverse=false},
    cooldown={x=321,y=-123,reverse=true},
}}
ns.InitializeDB()
assert(ns.db.bars.player.anchorKind=='health' and not ns.db.bars.player.reverse,'default player position adopts inward direction')
assert(ns.db.bars.target.anchorKind=='health' and ns.db.bars.target.reverse,'default target position adopts inward direction')
assert(ns.db.bars.focus.anchorKind=='portrait' and ns.db.bars.focus.offsetX==-7 and ns.db.bars.focus.offsetY==31 and not ns.db.bars.focus.reverse,'custom portrait position and explicit direction survive upgrade')
assert(ns.db.bars.cooldown.x==321 and ns.db.bars.cooldown.y==-123 and ns.db.bars.cooldown.reverse,'cooldown position and direction survive health layout migration')
ns.db.bars.target.reverse=false
ns.InitializeDB()
assert(not ns.db.bars.target.reverse and ns.db.bars.focus.anchorKind=='portrait','schema 5 reload does not reapply default directions or migrate custom portrait basis')
ns.ResetPositions()
assert(ns.db.bars.focus.anchorKind=='health' and ns.db.bars.focus.offsetX==-24 and ns.db.bars.focus.offsetY==24 and ns.db.bars.focus.reverse,'reset replaces custom portrait position with inward health layout')
assert(ns.db.bars.target.reverse and not ns.db.bars.player.reverse and ns.db.bars.cooldown.reverse,'reset restores DR directions without changing cooldown growth')
bjarkiCCDB={schema=4,bars={target={anchorKind='frame',offsetX=6,offsetY=-8,reverse=false}}}
ns.InitializeDB()
assert(ns.db.bars.target.anchorKind=='frame' and ns.db.bars.target.offsetX==6 and ns.db.bars.target.offsetY==-8 and not ns.db.bars.target.reverse,'explicit legacy frame basis survives even when its offsets resemble earlier defaults')
print('bootstrap: protected values, compact defaults, placement migration, bounded offsets and reset checks passed')
