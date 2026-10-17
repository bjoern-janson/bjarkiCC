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
assert(ns.db.bars.player.vertical == false and ns.db.targetOnly, 'valid preferences retained')
assert(ns.db.categories.stun == false and ns.db.categories.fear == true, 'category defaults merged')
assert(ns.db.resetSeconds >= 10 and ns.db.locked == true, 'malformed defaults recovered')
assert(ns.db.cooldownOverrides[853] == nil and ns.db.cooldownOverrides[408] == 30, 'overrides sanitized')
ns.db.bars.player.x = 300
ns.ResetPositions()
assert(ns.db.bars.player.x == -230 and ns.db.bars.player.vertical == false, 'reset adopts the fixed grid layout')

-- Loading without saved settings produces the compact, icon-only layout.
bjarkiCCDB = nil
ns.InitializeDB()
assert(ns.db.bars.player.size == 28 and ns.db.bars.target.size == 28, 'fresh DR bars use compact icons')
assert(ns.db.bars.focus, 'fresh settings include a focus DR bar')
assert(ns.db.bars.focus.size == 28 and ns.db.bars.focus.x == 230 and ns.db.bars.focus.y == -230, 'focus gets compact icons and its fallback placement')
assert(ns.db.bars.cooldown.size == 32, 'fresh cooldown bar uses compact icons')
assert(ns.db.showNames == false and ns.db.showDRText == false, 'fresh bars omit optional text')
assert(ns.db.resetSeconds == 20 and ns.db.stageResetSeconds == 18, 'application display and stage reset have independent defaults')
ns.db.resetSeconds, ns.db.stageResetSeconds = 24, 19
ns.InitializeDB()
assert(ns.db.resetSeconds == 24 and ns.db.stageResetSeconds == 19, 'both custom clock settings survive reload independently')
ns.db.stageResetSeconds = secret
ns.InitializeDB()
assert(ns.db.stageResetSeconds == 18 and ns.db.resetSeconds == 24, 'unreadable stage setting falls back without changing the application clock')
ns.db.stageResetSeconds = math.huge
ns.InitializeDB()
assert(ns.db.stageResetSeconds == 18, 'nonfinite stage reset uses its own default')
ns.db.stageResetSeconds = 99
ns.InitializeDB()
assert(ns.db.stageResetSeconds == 30, 'stage reset setting is bounded')
ns.db.resetSeconds, ns.db.stageResetSeconds = 20, 18
for _, key in ipairs({'player', 'target', 'focus', 'cooldown'}) do
    assert(ns.db.bars[key].gap == 3 and ns.db.bars[key].label == false, 'fresh bars have tight gaps and no labels')
end
local function sideDefaults()
    for _,key in ipairs({'player','target','focus'}) do
        local bar=ns.db.bars[key]
        assert(bar.anchorKind=='unit-side' and bar.offsetX==(key=='player' and -18 or 18) and bar.offsetY==0,
            'requested grid sits beyond the outer portrait edge with badge clearance')
        assert(not bar.vertical and bar.reverse==(key=='player') and bar.maxIcons==4,'fixed two-row grid is capped at four icons')
    end
end
sideDefaults()
assert(ns.db.bars.cooldown.offsetX==nil,'cooldowns keep free positioning')

-- This explicit layout request replaces every previous DR placement once.
-- All unrelated appearance, tracking, and cooldown layout choices survive.
for _,oldSchema in ipairs({0,1,2,3,4,5,6}) do
    bjarkiCCDB={schema=oldSchema,locked=false,targetOnly=true,interrupts=true,
        resetSeconds=24,stageResetSeconds=17,ownCastEstimates=false,
        categories={stun=false},disabledSpells={[853]=true},cooldownOverrides={[408]=45},
        bars={player={anchorKind='health',offsetX=71,offsetY=-33,size=44,gap=5,enabled=false,maxIcons=7},
            target={anchorKind='frame',offsetX=-55,offsetY=91,vertical=false,reverse=false},
            focus={anchorKind='portrait',offsetX=10,offsetY=0},
            cooldown={x=444,y=-333,size=48,gap=5,vertical=false,reverse=false,enabled=false}}}
    ns.InitializeDB(); sideDefaults()
    assert(ns.db.schema==7,'layout migration runs once')
    assert(ns.db.bars.player.size==44 and ns.db.bars.player.gap==5
        and not ns.db.bars.player.enabled and ns.db.bars.player.maxIcons==4,'DR appearance and enable preferences survive')
    local cd=ns.db.bars.cooldown
    assert(cd.x==444 and cd.y==-333 and cd.size==48 and cd.gap==5
        and not cd.vertical and not cd.reverse and not cd.enabled,'cooldown bar is unaffected by DR migration')
    assert(not ns.db.locked and ns.db.targetOnly and ns.db.interrupts and not ns.db.ownCastEstimates
        and ns.db.resetSeconds==24 and ns.db.stageResetSeconds==17,'tracking and both clocks survive')
    assert(not ns.db.categories.stun and ns.db.disabledSpells[853] and ns.db.cooldownOverrides[408]==45,
        'ability filters and cooldown overrides survive')
    ns.db.bars.target.offsetX,ns.db.bars.target.offsetY=15.5,-21.25
    ns.db.bars.target.vertical,ns.db.bars.target.reverse=false,false
    ns.InitializeDB()
    assert(ns.db.bars.target.offsetX==15.5 and ns.db.bars.target.offsetY==-21.25
        and not ns.db.bars.target.vertical and not ns.db.bars.target.reverse,'later reload preserves deliberate drag/layout changes')
    ns.ResetPositions(); sideDefaults()
    assert(ns.db.bars.cooldown.size==48 and not ns.db.bars.cooldown.vertical,'position reset preserves cooldown appearance and growth')
end
-- Existing compact visual migration still applies only to old visual defaults.
bjarkiCCDB={schema=1,bars={player={size=36,gap=8,label=true},cooldown={size=40,gap=8,label=true}}}
ns.InitializeDB()
assert(ns.db.bars.player.size==28 and ns.db.bars.player.gap==3 and not ns.db.bars.player.label,
    'old default DR styling still migrates')
assert(ns.db.bars.cooldown.size==32 and ns.db.bars.cooldown.gap==3,'old default cooldown styling still migrates')
ns.db.bars.player.size,ns.db.bars.player.gap=36,8
ns.InitializeDB()
assert(ns.db.bars.player.size==36 and ns.db.bars.player.gap==8,'visual migration is not reapplied')
bjarkiCCDB={schema=7,bars={player={anchorKind='unit-side',offsetX=secret,offsetY=0/0},
    target={anchorKind='unit-side',offsetX=math.huge,offsetY=-math.huge},
    focus={anchorKind='unit-side',offsetX=20001,offsetY=-20001}}}
ns.InitializeDB()
assert(ns.db.bars.player.offsetX==-18 and ns.db.bars.player.offsetY==0,'hidden and NaN offsets use safe defaults')
assert(ns.db.bars.target.offsetX==18 and ns.db.bars.target.offsetY==0,'infinite offsets use safe defaults')
assert(ns.db.bars.focus.offsetX==10000 and ns.db.bars.focus.offsetY==-10000,'finite offsets remain bounded')
print('bootstrap: protected values, compact defaults, centered portrait migration and saved preferences passed')
