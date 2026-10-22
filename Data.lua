-- bjarkiCC: explicit, provisional Classic rules for Forever beta.
-- DR classification adapted from DRList-1.0 (MIT), commit
-- 05c3c794fc18791d2173ea5361a6aa9c0029d91f. See THIRD_PARTY_NOTICES.txt.
-- No expansion autodetection: unknown project IDs must not select a different ruleset.
-- Cooldowns are estimates. Min/max do not cover every item, reset or beta change.

local _, ns = ...
ns.Data = {
    profile = "Classic baseline (provisional for Forever)",
    resetSeconds = 20,
    -- Next application after one, two, three successful observed applications.
    nextDuration = { 0.50, 0.25, 0 },
    categories = {
        { key = "stun", name = "Controlled Stun", short = "Stun", icon = "Interface\\Icons\\Spell_Holy_SealOfMight" },
        { key = "randomStun", name = "Random Stun", short = "Proc stun", icon = "Interface\\Icons\\Spell_Shadow_BlackPlague" },
        { key = "kidney", name = "Kidney Shot", short = "Kidney", icon = "Interface\\Icons\\Ability_Rogue_KidneyShot" },
        { key = "incapacitate", name = "Incapacitate / Disorient", short = "Incap", icon = "Interface\\Icons\\Spell_Nature_Polymorph" },
        { key = "fear", name = "Fear", short = "Fear", icon = "Interface\\Icons\\Spell_Shadow_Possession" },
        { key = "root", name = "Controlled Root", short = "Root", icon = "Interface\\Icons\\Spell_Frost_FrostNova" },
        { key = "randomRoot", name = "Random Root", short = "Proc root", icon = "Interface\\Icons\\Ability_Ensnare" },
        { key = "mindControl", name = "Mind Control", short = "MC", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate" },
        { key = "frostShock", name = "Frost Shock", short = "Frost shock", icon = "Interface\\Icons\\Spell_Frost_FrostShock" },
    },
    categoryByKey = {},
    -- Aura/effect IDs only. A successful cast alone must never advance DR.
    -- Season of Discovery's Deep Freeze 428739 and Between the Eyes 400009
    -- are deliberately excluded. New Forever abilities are not guessed.
    auraCategory = {
        [339]   = "root", -- Entangling Roots (Rank 1)
        [1062]  = "root", -- Entangling Roots (Rank 2)
        [5195]  = "root", -- Entangling Roots (Rank 3)
        [5196]  = "root", -- Entangling Roots (Rank 4)
        [9852]  = "root", -- Entangling Roots (Rank 5)
        [9853]  = "root", -- Entangling Roots (Rank 6)
        [19975] = "root", -- Nature's Grasp (Rank 1)
        [19974] = "root", -- Nature's Grasp (Rank 2)
        [19973] = "root", -- Nature's Grasp (Rank 3)
        [19972] = "root", -- Nature's Grasp (Rank 4)
        [19971] = "root", -- Nature's Grasp (Rank 5)
        [19970] = "root", -- Nature's Grasp (Rank 6)
        [19306] = "root", -- Counterattack (Rank 1)
        [20909] = "root", -- Counterattack (Rank 2)
        [20910] = "root", -- Counterattack (Rank 3)
        [122]   = "root", -- Frost Nova (Rank 1)
        [865]   = "root", -- Frost Nova (Rank 2)
        [6131]  = "root", -- Frost Nova (Rank 3)
        [10230] = "root", -- Frost Nova (Rank 4)
        [19229] = "randomRoot", -- Improved Wing Clip
        [23694] = "randomRoot", -- Improved Hamstring
        [27868] = "randomRoot", -- Freeze (Item Proc)
        [5211]  = "stun", -- Bash (Rank 1)
        [6798]  = "stun", -- Bash (Rank 2)
        [8983]  = "stun", -- Bash (Rank 3)
        [9005]  = "stun", -- Pounce (Rank 1)
        [9823]  = "stun", -- Pounce (Rank 2)
        [9827]  = "stun", -- Pounce (Rank 3)
        [24394] = "stun", -- Intimidation
        [853]   = "stun", -- Hammer of Justice (Rank 1)
        [5588]  = "stun", -- Hammer of Justice (Rank 2)
        [5589]  = "stun", -- Hammer of Justice (Rank 3)
        [10308] = "stun", -- Hammer of Justice (Rank 4)
        [1833]  = "stun", -- Cheap Shot
        [12809] = "stun", -- Concussion Blow
        [20253] = "stun", -- Intercept Stun (Rank 1)
        [20614] = "stun", -- Intercept Stun (Rank 2)
        [20615] = "stun", -- Intercept Stun (Rank 3)
        [7922]  = "stun", -- Charge Stun
        [20549] = "stun", -- War Stomp (Racial)
        [4068]  = "stun", -- Iron Grenade (Item)
        [19769] = "stun", -- Thorium Grenade (Item)
        [13808] = "stun", -- M73 Frag Grenade (Item)
        [4069]  = "stun", -- Big Iron Bomb (Item)
        [12543] = "stun", -- Hi-Explosive Bomb (Item)
        [4064]  = "stun", -- Rough Copper Bomb (Item)
        [12421] = "stun", -- Mithril Frag Bomb (Item)
        [19784] = "stun", -- Dark Iron Bomb (Item)
        [4067]  = "stun", -- Big Bronze Bomb (Item)
        [4066]  = "stun", -- Small Bronze Bomb (Item)
        [4065]  = "stun", -- Large Copper Bomb (Item)
        [13237] = "stun", -- Goblin Mortar (Item)
        [835]   = "stun", -- Tidal Charm (Item)
        [12562] = "stun", -- The Big One (Item)
        [16922] = "randomStun", -- Celestial Focus (Improved Starfire)
        [19410] = "randomStun", -- Improved Concussive Shot
        [12355] = "randomStun", -- Impact
        [20170] = "randomStun", -- Seal of Justice Stun
        [15269] = "randomStun", -- Blackout
        [18093] = "randomStun", -- Pyroclasm
        [12798] = "randomStun", -- Revenge Stun
        [5530]  = "randomStun", -- Mace Stun Effect (Mace Specialization)
        [15283] = "randomStun", -- Stunning Blow (Weapon Proc)
        [56]    = "randomStun", -- Stun (Weapon Proc)
        [21152] = "randomStun", -- Earthshaker (Weapon Proc)
        [2637]  = "incapacitate", -- Hibernate (Rank 1)
        [18657] = "incapacitate", -- Hibernate (Rank 2)
        [18658] = "incapacitate", -- Hibernate (Rank 3)
        [3355]  = "incapacitate", -- Freezing Trap Effect (Rank 1)
        [14308] = "incapacitate", -- Freezing Trap Effect (Rank 2)
        [14309] = "incapacitate", -- Freezing Trap Effect (Rank 3)
        [19503] = "incapacitate", -- Scatter Shot
        [19386] = "incapacitate", -- Wyvern Sting (Rank 1)
        [24132] = "incapacitate", -- Wyvern Sting (Rank 2)
        [24133] = "incapacitate", -- Wyvern Sting (Rank 3)
        [118]   = "incapacitate", -- Polymorph (Rank 1)
        [12824] = "incapacitate", -- Polymorph (Rank 2)
        [12825] = "incapacitate", -- Polymorph (Rank 3)
        [12826] = "incapacitate", -- Polymorph (Rank 4)
        [28271] = "incapacitate", -- Polymorph: Turtle
        [28272] = "incapacitate", -- Polymorph: Pig
        [20066] = "incapacitate", -- Repentance
        [1776]  = "incapacitate", -- Gouge (Rank 1)
        [1777]  = "incapacitate", -- Gouge (Rank 2)
        [8629]  = "incapacitate", -- Gouge (Rank 3)
        [11285] = "incapacitate", -- Gouge (Rank 4)
        [11286] = "incapacitate", -- Gouge (Rank 5)
        [6770]  = "incapacitate", -- Sap (Rank 1)
        [2070]  = "incapacitate", -- Sap (Rank 2)
        [11297] = "incapacitate", -- Sap (Rank 3)
        [1090]  = "incapacitate", -- Sleep (Item Magic Dust)
        [700]   = "incapacitate", -- Sleep (Item Slumber Sand)
        [13327] = "incapacitate", -- Reckless Charge (Item)
        [26108] = "incapacitate", -- Glimpse of Madness (Item)
        [1513]  = "fear", -- Scare Beast (Rank 1)
        [14326] = "fear", -- Scare Beast (Rank 2)
        [14327] = "fear", -- Scare Beast (Rank 3)
        [8122]  = "fear", -- Psychic Scream (Rank 1)
        [8124]  = "fear", -- Psychic Scream (Rank 2)
        [10888] = "fear", -- Psychic Scream (Rank 3)
        [10890] = "fear", -- Psychic Scream (Rank 4)
        [5782]  = "fear", -- Fear (Rank 1)
        [6213]  = "fear", -- Fear (Rank 2)
        [6215]  = "fear", -- Fear (Rank 3)
        [5484]  = "fear", -- Howl of Terror (Rank 1)
        [17928] = "fear", -- Howl of Terror (Rank 2)
        [6358]  = "fear", -- Seduction (Succubus)
        [5246]  = "fear", -- Intimidating Shout
        [5134]  = "fear", -- Flash Bomb (Item)
        [408]    = "kidney",  -- Kidney Shot (Rank 1)
        [8643]   = "kidney",  -- Kidney Shot (Rank 2)
        [605]    = "mindControl", -- Mind Control (Rank 1)
        [10911]  = "mindControl", -- Mind Control (Rank 2)
        [10912]  = "mindControl", -- Mind Control (Rank 3)
        [13181]  = "mindControl", -- Gnomish Mind Control Cap (Item)
        [8056]   = "frostShock",  -- Frost Shock (Rank 1)
        [8058]   = "frostShock",  -- Frost Shock (Rank 2)
        [10472]  = "frostShock",  -- Frost Shock (Rank 3)
        [10473]  = "frostShock",  -- Frost Shock (Rank 4)
        -- Verified new Forever Counterattack rank. Its assignment to the
        -- family's Classic root DR remains part of this provisional profile.
        [1242634] = "root",
    },
    spells = {},
    castToSpell = {},
    -- Exact positive aura evidence for abilities that are self-activated.
    -- Never infer Innervate/Freedom/etc. from the recipient alone.
    helpfulCooldownAuras = {},
    -- Landed player loss-of-control EFFECTS, not general DR category clues.
    -- The source caster is UNKNOWN; do not map a Nature's Grasp proc root
    -- back to a new Nature's Grasp activation or use delayed trap triggers.
    locCooldownEffects = {},
    -- Only tracked cooldowns affected by historically documented reset families.
    -- These reset spells are inputs, not CC cooldown icons of their own.
    resets = {
        [12472] = { 122 },                -- Cold Snap -> Frost Nova
        [14185] = { 408, 2094, 1776 },   -- Preparation -> Kidney Shot, Blind, Gouge
    },
}

local Data = ns.Data
for i = 1, #Data.categories do
    local category = Data.categories[i]
    Data.categoryByKey[category.key] = category
end

-- Presentation categories for cooldowns only. They are not DR categories.
Data.categoryByKey.horror = {
    key = "horror", name = "Horror (cooldown only)", short = "Horror",
    icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
}
Data.categoryByKey.disorient = {
    key = "disorient", name = "Disorient (cooldown only)", short = "Blind",
    icon = "Interface\\Icons\\Spell_Shadow_MindSteal",
}
Data.categoryByKey.interrupt = {
    key = "interrupt", name = "Interrupt (cooldown only)", short = "Interrupt",
    icon = "Interface\\Icons\\Ability_Kick",
}
Data.categoryByKey.defensive = {
    key = "defensive", name = "Defense (cooldown only)", short = "Defense",
    icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
}

local function AddSpell(id, name, category, texture, cdMin, cdMax, ranks, interrupt)
    Data.spells[id] = {
        id = id, name = name, category = category,
        icon = "Interface\\Icons\\" .. texture,
        cdMin = cdMin, cdMax = cdMax, interrupt = interrupt or nil,
    }
    Data.castToSpell[id] = id
    if ranks then
        for i = 1, #ranks do Data.castToSpell[ranks[i]] = id end
    end
end

-- Historical Classic cooldown registry, with selected Forever client-data bounds.
-- Fixed estimates below are not proof that all talents/items were accounted for.
-- HoJ includes 0-3 points in Improved HoJ, but not every possible set bonus.
AddSpell(853, "Hammer of Justice", "stun", "Spell_Holy_SealOfMight", 45, 60, { 5588, 5589, 10308 })
AddSpell(20066, "Repentance", "incapacitate", "Spell_Holy_PrayerOfHealing", 60, 60)
-- Forever Brutal Impact now reduces Bash by 15/30s.
AddSpell(5211, "Bash", "stun", "Ability_Druid_Bash", 30, 60, { 6798, 8983 })
AddSpell(16689, "Nature's Grasp", "root", "Spell_Nature_NaturesWrath", 60, 60, { 16810, 16811, 16812, 16813, 17329 })
-- Cooldown predictions from a new, readable, self-applied helpful aura.
-- These are provisional Forever timings, not server-authoritative readiness.
AddSpell(22812, "Barkskin", "defensive", "Spell_Nature_StoneClawTotem", 60, 60)
AddSpell(5277, "Evasion", "defensive", "Spell_Shadow_ShadowWard", 210, 300, {26669})
AddSpell(122, "Frost Nova", "root", "Spell_Frost_FrostNova", 21, 25, { 865, 6131, 10230 })
AddSpell(408, "Kidney Shot", "kidney", "Ability_Rogue_KidneyShot", 20, 20, { 8643 })
-- Blind and Death Coil have no DR entry in this Classic mapping.
AddSpell(2094, "Blind", "disorient", "Spell_Shadow_MindSteal", 180, 300)
AddSpell(1776, "Gouge", "incapacitate", "Ability_Gouge", 9, 10, { 1777, 8629, 11285, 11286 })
AddSpell(8122, "Psychic Scream", "fear", "Spell_Shadow_PsychicScream", 26, 30, { 8124, 10888, 10890 })
AddSpell(5484, "Howl of Terror", "fear", "Spell_Shadow_DeathScream", 40, 40, { 17928 })
AddSpell(6789, "Death Coil", "horror", "Spell_Shadow_DeathCoil", 102, 120, { 17925, 17926 })
-- Trap cast IDs differ from trap effect IDs 3355/14308/14309 in auraCategory.
-- Forever increases this cast cooldown from Classic's 15s to 30s.
AddSpell(1499, "Freezing Trap", "incapacitate", "Spell_Frost_ChainsOfIce", 30, 30, { 14310, 14311 })
AddSpell(19386, "Wyvern Sting", "incapacitate", "INV_Spear_02", 120, 120, { 24132, 24133 })
AddSpell(19503, "Scatter Shot", "incapacitate", "Ability_GolemStormBolt", 30, 30)
-- Intimidation is cast by the hunter as 19577; the later stun effect is 24394.
AddSpell(19577, "Intimidation", "stun", "Ability_Devour", 60, 60)
AddSpell(19306, "Counterattack", "root", "Ability_Hunter_SwiftStrike", 5, 5, { 1242634, 20909, 20910 })
AddSpell(12809, "Concussion Blow", "stun", "Ability_ThunderBolt", 45, 45)
AddSpell(5246, "Intimidating Shout", "fear", "Ability_GolemThunderClap", 180, 180)
-- Official October 15 beta notes reduce War Stomp from 120s to 90s.
AddSpell(20549, "War Stomp", "stun", "Ability_WarStomp", 90, 90)
-- Charge/Intercept cast IDs differ from their stun effect IDs.
AddSpell(100, "Charge", "stun", "Ability_Warrior_Charge", 15, 15, { 6178, 11578 })
-- Improved Intercept reduces its 30s base cooldown by 5/10s.
AddSpell(20252, "Intercept", "stun", "Ability_Rogue_Sprint", 20, 30, { 20616, 20617 })

-- Optional interrupt families.
AddSpell(1766, "Kick", "interrupt", "Ability_Kick", 10, 10, { 1767, 1768, 1769 }, true)
AddSpell(6552, "Pummel", "interrupt", "INV_Gauntlets_04", 10, 10, { 6554 }, true)
AddSpell(72, "Shield Bash", "interrupt", "Ability_Warrior_ShieldBash", 12, 12, { 1671, 1672 }, true)
AddSpell(2139, "Counterspell", "interrupt", "Spell_Frost_IceShock", 30, 30, nil, true)
AddSpell(19244, "Spell Lock", "interrupt", "Spell_Shadow_MindRot", 30, 30, { 19647 }, true)
-- Classic shocks share a cooldown: any observed shock starts this one family.
-- Its label intentionally does not claim that the enemy cast Earth Shock.
-- Frost Shock's DR category remains separate in auraCategory.
AddSpell(8042, "Shocks (shared cooldown)", "frostShock", "Spell_Nature_EarthShock", 5, 6, {
    8044, 8045, 8046, 10412, 10413, 10414,
    8050, 8052, 8053, 10447, 10448, 29228,
    8056, 8058, 10472, 10473,
})


-- Positive-only inference. Beneficial aura on another player does NOT prove
-- its recipient cast it unless the ability can only target the caster.
for _, id in ipairs({16689,16810,16811,16812,16813,17329,22812,5277,26669}) do
    local canonical = Data.castToSpell[id]
    if canonical and Data.spells[canonical] then Data.helpfulCooldownAuras[id] = canonical end
end

-- LoC spell IDs below correspond closely to the use of the cooldown spell.
-- Traps (late trigger), Nature's Grasp proc roots (later trigger), and generic
-- CC effects with unknown originating ability are intentionally excluded.
for effectID, castID in pairs({
    [853]=853,[5588]=853,[5589]=853,[10308]=853, -- Hammer of Justice
    [5211]=5211,[6798]=5211,[8983]=5211, -- Bash
    [408]=408,[8643]=408, -- Kidney Shot
    [8122]=8122,[8124]=8122,[10888]=8122,[10890]=8122, -- Psychic Scream
    [5484]=5484,[17928]=5484, -- Howl of Terror
    [122]=122,[865]=122,[6131]=122,[10230]=122, -- Frost Nova
    [20549]=20549, -- War Stomp
    [20066]=20066, -- Repentance
    [19503]=19503, -- Scatter Shot
    [19386]=19386,[24132]=19386,[24133]=19386, -- Wyvern Sting
    [12809]=12809, -- Concussion Blow
}) do
    if Data.spells[castID] then Data.locCooldownEffects[effectID] = castID end
end
