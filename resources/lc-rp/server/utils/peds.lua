-- utils/peds.lua
-- Whitelist of allowed ped models for character creation.
-- Must match client peds.js. See https://happinessmp.net/docs/game/models/peds

Peds = {}

-- Blacklist: public service, emergency, government, prison, military (rejected even if whitelisted)
local PEDS_BLACKLIST = {
    ["M_M_ARMOURED"] = true, ["M_M_busdriver"] = true, ["M_M_doc_scrubs_01"] = true,
    ["M_M_doctor_01"] = true, ["M_M_DODGYDOC"] = true, ["M_M_FatCop_01"] = true,
    ["M_M_FBI"] = true, ["M_M_FedCo"] = true, ["M_M_Firechief"] = true,
    ["M_M_GunNut_01"] = true, ["M_M_Helipilot_01"] = true, ["M_M_pilot"] = true,
    ["M_M_Postal_01"] = true, ["M_M_Train_01"] = true, ["M_O_Janitor"] = true,
    ["M_Y_airworker"] = true, ["M_Y_Cop"] = true, ["M_Y_Cop_Traffic"] = true,
    ["M_Y_Fireman"] = true, ["M_Y_NHelipilot"] = true, ["M_Y_pmedic"] = true,
    ["M_Y_STROOPER"] = true, ["M_Y_Swat"] = true,
    ["IG_BillyPrison"] = true, ["IG_Desean"] = true, ["IG_STrooper"] = true,
    ["M_Y_CIAdlc_01"] = true, ["M_Y_CIAdlc_02"] = true, ["M_Y_PrisonDLC_01"] = true,
    ["M_Y_Prisonguard"] = true, ["M_Y_PrisonBlack"] = true,
    ["IG_Mori_K"] = true, ["superlod"] = true, ["ig_RomanW"] = true,
}

local MALE_PEDS = {
    ["M_Y_MULTIPLAYER"] = true,
    ["ig_Roman"] = true, ["ig_Brucie"] = true, ["ig_Packie_Mc"] = true, ["ig_Dwayne"] = true,
    ["ig_Brian"] = true, ["ig_Anthony"] = true, ["ig_Badman"] = true, ["ig_Bernie_Crane"] = true,
    ["ig_Bledar"] = true, ["ig_Bulgarin"] = true, ["ig_CharlieUC"] = true, ["ig_Clarence"] = true,
    ["ig_Dardan"] = true, ["ig_Darko"] = true, ["ig_Derrick_Mc"] = true, ["ig_Dmitri"] = true,
    ["ig_EddieLow"] = true, ["ig_Faustin"] = true, ["ig_Francis_Mc"] = true, ["ig_French_Tom"] = true,
    ["ig_Gordon"] = true, ["ig_Hossan"] = true, ["ig_Isaac"] = true, ["ig_Ivan"] = true,
    ["ig_Jay"] = true, ["ig_Jason"] = true, ["ig_Jeff"] = true, ["ig_Jimmy"] = true,
    ["ig_JohnnyBiker"] = true, ["ig_Kenny"] = true, ["ig_LilJacob"] = true, ["ig_Luca"] = true,
    ["ig_Luis"] = true, ["ig_Manny"] = true, ["ig_Mel"] = true, ["ig_Michael"] = true,
    ["ig_Mickey"] = true, ["ig_Pathos"] = true, ["ig_Petrovic"] = true, ["ig_Phil_Bell"] = true,
    ["ig_Playboy_X"] = true, ["ig_Ray_Boccino"] = true, ["ig_Ricky"] = true, ["ig_Tuna"] = true,
    ["ig_Vinny_Spaz"] = true, ["ig_Vlad"] = true,
    ["M_Y_business_01"] = true, ["M_Y_business_02"] = true, ["M_Y_Downtown_01"] = true,
    ["M_Y_Downtown_02"] = true, ["M_Y_Downtown_03"] = true, ["M_Y_GenStreet_11"] = true,
    ["M_Y_GenStreet_16"] = true, ["M_Y_GenStreet_20"] = true, ["M_Y_GenStreet_34"] = true,
    ["M_Y_PManhat_01"] = true, ["M_Y_PManhat_02"] = true, ["M_Y_PCool_01"] = true, ["M_Y_PCool_02"] = true,
    ["M_Y_PLatin_01"] = true, ["M_Y_PLatin_02"] = true, ["M_Y_PLatin_03"] = true,
    ["M_Y_PBronx_01"] = true, ["M_Y_PHarbron_01"] = true, ["M_Y_PHarlem_01"] = true,
    ["M_Y_PJersey_01"] = true, ["M_Y_PQueens_01"] = true, ["M_Y_PRich_01"] = true,
    ["M_Y_PEastEuro_01"] = true, ["M_Y_POrient_01"] = true, ["M_Y_street_01"] = true,
    ["M_Y_street_03"] = true, ["M_Y_street_04"] = true, ["M_Y_BoHo_01"] = true, ["M_Y_Bronx_01"] = true,
    ["M_Y_Harlem_01"] = true, ["M_Y_Harlem_02"] = true, ["M_Y_Harlem_04"] = true,
    ["M_Y_soho_01"] = true, ["M_Y_Queensbridge"] = true,
    ["M_Y_barman_01"] = true, ["M_Y_bouncer_01"] = true, ["M_Y_construct_01"] = true,
    ["M_Y_Mechanic_02"] = true, ["M_Y_Taxidriver"] = true, ["M_Y_Vendor"] = true,
    ["M_Y_Valet"] = true, ["M_Y_Gymguy_01"] = true, ["M_M_business_02"] = true,
    ["M_M_Business_03"] = true, ["M_M_PBusiness_01"] = true, ["M_M_PManhat_01"] = true,
    ["M_M_PManhat_02"] = true, ["M_M_PLatin_01"] = true, ["M_M_PLatin_02"] = true,
    ["M_M_PLatin_03"] = true, ["M_M_PRich_01"] = true, ["M_M_PItalian_01"] = true,
    ["M_O_suited"] = true, ["M_O_Mobster"] = true, ["M_O_street_01"] = true,
}

local FEMALE_PEDS = {
    ["F_Y_MULTIPLAYER"] = true,
    ["ig_Anna"] = true, ["ig_Charise"] = true, ["ig_Gracie"] = true, ["ig_KateMc"] = true,
    ["ig_Mallorie"] = true, ["ig_Marnie"] = true, ["ig_Michelle"] = true, ["ig_Sarah"] = true,
    ["ig_MaMc"] = true,
    ["F_Y_Business_01"] = true, ["F_Y_Cdress_01"] = true, ["F_Y_PManhat_01"] = true,
    ["F_Y_PManhat_02"] = true, ["F_Y_PManhat_03"] = true, ["F_Y_PCool_01"] = true, ["F_Y_PCool_02"] = true,
    ["F_Y_PLatin_01"] = true, ["F_Y_PLatin_02"] = true, ["F_Y_PLatin_03"] = true,
    ["F_Y_PBronx_01"] = true, ["F_Y_PHarlem_01"] = true, ["F_Y_PJersey_02"] = true,
    ["F_Y_PQueens_01"] = true, ["F_Y_PRich_01"] = true, ["F_Y_PEastEuro_01"] = true,
    ["F_Y_PHarBron_01"] = true, ["F_Y_POrient_01"] = true, ["F_Y_street_02"] = true,
    ["F_Y_street_05"] = true, ["F_Y_street_09"] = true, ["F_Y_street_12"] = true,
    ["F_Y_street_30"] = true, ["F_Y_street_34"] = true, ["F_Y_Socialite"] = true,
    ["F_Y_shop_03"] = true, ["F_Y_shop_04"] = true, ["F_Y_shopper_05"] = true,
    ["F_Y_villbo_01"] = true, ["F_Y_Tourist_01"] = true, ["F_Y_waitress_01"] = true,
    ["F_Y_Gymgal_01"] = true, ["F_M_Business_01"] = true, ["F_M_Business_02"] = true,
    ["F_M_PManhat_01"] = true, ["F_M_PManhat_02"] = true, ["F_M_PRich_01"] = true,
}

function Peds.isValidSkin(skin, gender)
    if type(skin) ~= "string" or #skin == 0 then return false end
    if PEDS_BLACKLIST[skin] then return false end
    local set = (type(gender) == "string" and gender:lower() == "female") and FEMALE_PEDS or MALE_PEDS
    return set[skin] == true
end
