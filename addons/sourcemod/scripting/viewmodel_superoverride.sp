#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/econ>
#include <tf_custom_attributes>
#include <stocksoup/var_strings>

#include <tf_econ_data>
#include <tf2utils>

#define OBS_MODE_IN_EYE 4

#define TF_ITEM_DEFINDEX_GUNSLINGER 142

enum PlayerAnimEvent_t
{
	PLAYERANIMEVENT_ATTACK_PRIMARY,
	PLAYERANIMEVENT_ATTACK_SECONDARY,
	PLAYERANIMEVENT_ATTACK_GRENADE,
	PLAYERANIMEVENT_RELOAD,
	PLAYERANIMEVENT_RELOAD_LOOP,
	PLAYERANIMEVENT_RELOAD_END,
	PLAYERANIMEVENT_JUMP,
	PLAYERANIMEVENT_SWIM,
	PLAYERANIMEVENT_DIE,
	PLAYERANIMEVENT_FLINCH_CHEST,
	PLAYERANIMEVENT_FLINCH_HEAD,
	PLAYERANIMEVENT_FLINCH_LEFTARM,
	PLAYERANIMEVENT_FLINCH_RIGHTARM,
	PLAYERANIMEVENT_FLINCH_LEFTLEG,
	PLAYERANIMEVENT_FLINCH_RIGHTLEG,
	PLAYERANIMEVENT_DOUBLEJUMP,

	// Cancel.
	PLAYERANIMEVENT_CANCEL,
	PLAYERANIMEVENT_SPAWN,

	// Snap to current yaw exactly
	PLAYERANIMEVENT_SNAP_YAW,

	PLAYERANIMEVENT_CUSTOM,				// Used to play specific activities
	PLAYERANIMEVENT_CUSTOM_GESTURE,
	PLAYERANIMEVENT_CUSTOM_SEQUENCE,	// Used to play specific sequences
	PLAYERANIMEVENT_CUSTOM_GESTURE_SEQUENCE,

	// TF Specific. Here until there's a derived game solution to this.
	PLAYERANIMEVENT_ATTACK_PRE,
	PLAYERANIMEVENT_ATTACK_POST,
	PLAYERANIMEVENT_GRENADE1_DRAW,
	PLAYERANIMEVENT_GRENADE2_DRAW,
	PLAYERANIMEVENT_GRENADE1_THROW,
	PLAYERANIMEVENT_GRENADE2_THROW,
	PLAYERANIMEVENT_VOICE_COMMAND_GESTURE,
	PLAYERANIMEVENT_DOUBLEJUMP_CROUCH,
	PLAYERANIMEVENT_STUN_BEGIN,
	PLAYERANIMEVENT_STUN_MIDDLE,
	PLAYERANIMEVENT_STUN_END,
	PLAYERANIMEVENT_PASSTIME_THROW_BEGIN,
	PLAYERANIMEVENT_PASSTIME_THROW_MIDDLE,
	PLAYERANIMEVENT_PASSTIME_THROW_END,
	PLAYERANIMEVENT_PASSTIME_THROW_CANCEL,

	PLAYERANIMEVENT_ATTACK_PRIMARY_SUPER,

	PLAYERANIMEVENT_COUNT
};

bool g_bIgnoreWeaponSwitch[MAXPLAYERS + 1];
bool g_iIsCritAttack[MAXPLAYERS + 1];

static int g_iSuperViewModelRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
static int g_iSuperArmModelRef[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};

StringMap g_MissingModels;

public void OnPluginStart()
{
	GameData gamedata = new GameData("vm_superoverride");
	if (gamedata == null)
		SetFailState("Could not find vm_superoverride gamedata");
	DHook_Setup(gamedata);

	delete gamedata;
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	PrecacheModel("models/weapons/c_models/c_scout_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_sniper_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_soldier_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_demo_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_medic_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_heavy_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_pyro_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_spy_arms.mdl");
	PrecacheModel("models/weapons/c_models/c_engineer_arms.mdl");

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("post_inventory_application", OnInventoryAppliedPost);
	
	delete g_MissingModels;
	g_MissingModels = new StringMap();
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			ViewModel_Destroy(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_Spawn, OnPlayerSpawnPre);
	SDKHook(client, SDKHook_SpawnPost, OnPlayerSpawnPost);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
}

void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client) {
		ViewModel_Destroy(client);
	}
}

void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client) {
		return;
	}
	Create_Viewmodel(client);
	
	/**
	 * start processing weapon switches, since other plugins may be equipping new weapons in
	 * post_inventory_application -- and that's still within the player's spawn function call
	 */
	g_bIgnoreWeaponSwitch[client] = false;
}

Action OnPlayerSpawnPre(int client)
{
	g_bIgnoreWeaponSwitch[client] = true;
	return Plugin_Continue;
}

void OnPlayerSpawnPost(int client)
{
	g_bIgnoreWeaponSwitch[client] = false;
}

void OnWeaponSwitchPost(int client, int weapon)
{
	if (!g_bIgnoreWeaponSwitch[client]) {
		Create_Viewmodel(client);
	}
}

public void Create_Viewmodel(int client)
{
	ViewModel_Destroy(client);

	int weapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(weapon)) {
		return;
	}

	char svm[PLATFORM_MAX_PATH];
	if (TF2CustAttr_GetString(weapon, "viewmodel superoverride", svm, sizeof(svm))
			&& FileExistsAndLog(svm, true)) {
		// override viewmodel by attaching arm and weapon viewmodels
		PrecacheModelAndLog(svm);

		float superangleoffset[3] = {0.0, 0.0, 0.0};
		float height = 0.0;
		char attr[64];
		if (TF2CustAttr_GetString(weapon, "viewmodel superoffset", attr, sizeof(attr)))
		{
			superangleoffset[0] = ReadFloatVar(attr, "x", 0.0);
			superangleoffset[1] = ReadFloatVar(attr, "y", 0.0);
			superangleoffset[2] = ReadFloatVar(attr, "z", 0.0);
			height = ReadFloatVar(attr, "h", 0.0);
		}
		
		ViewModel_Create(client, svm, superangleoffset, height);

		OriginalViewModel_Hide(client);
	}
}

bool FileExistsAndLog(const char[] path, bool use_valve_fs = false,
		const char[] valve_path_id = "GAME")
{
	if (FileExists(path, use_valve_fs, valve_path_id)) {
		return true;
	}
	
	any discarded;
	if (!g_MissingModels.GetValue(path, discarded)) {
		LogError("Missing file '%s'", path);
		g_MissingModels.SetValue(path, true);
	}
	return false;
}

int PrecacheModelAndLog(const char[] model, bool preload = false)
{
	int modelIndex = PrecacheModel(model, preload);
	if (!modelIndex) {
		LogError("Failed to precache model '%s'", model);
	}
	return modelIndex;
}

// viewmodel!

void ViewModel_Create(int iClient, const char[] sModel, const float vecAnglesOffset[3] = NULL_VECTOR, float flHeight = 0.0)
{
	int weapon = TF2_GetClientActiveWeapon(iClient);
	
	int iViewModel = CreateEntityByName("prop_dynamic");
	if (iViewModel <= MaxClients)
		return;
	
	SetEntPropEnt(iViewModel, Prop_Send, "m_hOwnerEntity", iClient);
	if (TF2CustAttr_GetInt(weapon, "viewmodel superoverride skin"))
	{
		int iSkin = TF2CustAttr_GetInt(weapon, "viewmodel superoverride skin");
		SetEntProp(iViewModel, Prop_Send, "m_nSkin", iSkin);
	}
	else
	{
		SetEntProp(iViewModel, Prop_Send, "m_nSkin", GetClientTeam(iClient) - 2);
	}
	
	DispatchKeyValue(iViewModel, "model", sModel);
	DispatchKeyValue(iViewModel, "disablereceiveshadows", "0");
	DispatchKeyValue(iViewModel, "disableshadows", "1");
	
	float vecOrigin[3], vecAngles[3];
	GetClientAbsOrigin(iClient, vecOrigin);
	GetClientAbsAngles(iClient, vecAngles);
	
	vecOrigin[2] += flHeight;
	AddVectors(vecAngles, vecAnglesOffset, vecAngles);
	
	TeleportEntity(iViewModel, vecOrigin, vecAngles, NULL_VECTOR);
	DispatchSpawn(iViewModel);
	
	SetVariantString("!activator");
	AcceptEntityInput(iViewModel, "SetParent", GetEntPropEnt(iClient, Prop_Send, "m_hViewModel"));

	SDKHook(iViewModel, SDKHook_SetTransmit, ViewModel_SetTransmit);
	
	g_iSuperViewModelRef[iClient] = EntIndexToEntRef(iViewModel);

	char asvm[PLATFORM_MAX_PATH];
	char advm[PLATFORM_MAX_PATH];
	GetArmViewModel(iClient, advm, sizeof(advm));
	if (TF2CustAttr_GetString(weapon, "armmodel superoverride", asvm, sizeof(asvm), advm))
	{
		if (!StrEqual(asvm, "none"))
		{
			// if the viewmodel gets killed, this will automatically delete itself due to hierarchy
			int iHands = CreateEntityByName("prop_dynamic");
			if (IsValidEntity(iHands))
			{
				int meleeWeapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Melee);
				if (IsValidEntity(meleeWeapon)
						&& TF2_GetItemDefinitionIndex(meleeWeapon) == TF_ITEM_DEFINDEX_GUNSLINGER) {
					char armvmpath[PLATFORM_MAX_PATH];
					if(TF2CustAttr_GetString(meleeWeapon, "arm model override", armvmpath, sizeof(armvmpath)) && FileExistsAndLog(armvmpath, true))
					{
						PrecacheModelAndLog(armvmpath);
						DispatchKeyValue(iHands, "model", armvmpath);
					}
					else
					{
						DispatchKeyValue(iHands, "model", "models/weapons/c_models/c_engineer_gunslinger.mdl");
					}
				}
				else
				{
					DispatchKeyValue(iHands, "model", asvm);
				}
				DispatchKeyValue(iHands, "solid", "0");
				DispatchKeyValue(iHands, "effects", "129");
				DispatchKeyValue(iHands, "disableshadows", "1");

				int skin = GetClientTeam(iClient) - 2;
				if (skin < 0)
					skin = 0;
				SetEntProp(iHands, Prop_Send, "m_nSkin", skin);

				TeleportEntity(iHands, vecOrigin, vecAngles, NULL_VECTOR);

				DispatchSpawn(iHands);
				ActivateEntity(iHands);
				
				SetVariantString("!activator");
				AcceptEntityInput(iHands, "SetParent", iViewModel, iViewModel);	
				
				char attach[32];
				TF2CustAttr_GetString(weapon, "armmodel attachment", attach, sizeof(attach), "weapon_bone");
				SetVariantString(attach);
				AcceptEntityInput(iHands, "SetParentAttachment", iViewModel, iViewModel);

				g_iSuperArmModelRef[iClient] = EntIndexToEntRef(iHands);
			}	
		}
	}
	
	char attr[512];
	if(TF2CustAttr_GetString(weapon, "vm superoverride anim", attr, sizeof(attr)))
	{
		char Draw[32], Idle[32];
		ReadStringVar(attr, "idle", Idle, sizeof(Idle), "idle");
		ViewModel_SetDefaultAnimation(iClient, Idle);
			
		ReadStringVar(attr, "draw", Draw, sizeof(Draw), "draw");
		ViewModel_SetAnimation(iClient, Draw);

		float flPlayBackRate = GetEntPropFloat(iClient, Prop_Send, "m_flPlaybackRate");
		ViewModel_SetPlaybackRate(iClient, flPlayBackRate);

		HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
	}
	else
	{
		ViewModel_SetDefaultAnimation(iClient, "idle");
		ViewModel_SetAnimation(iClient, "draw");
	}

	return;
}

int GetArmViewModel(int client, char[] buffer, int maxlen) {
	static char armModels[TFClassType][] = {
		"",
		"models/weapons/c_models/c_scout_arms.mdl",
		"models/weapons/c_models/c_sniper_arms.mdl",
		"models/weapons/c_models/c_soldier_arms.mdl",
		"models/weapons/c_models/c_demo_arms.mdl",
		"models/weapons/c_models/c_medic_arms.mdl",
		"models/weapons/c_models/c_heavy_arms.mdl",
		"models/weapons/c_models/c_pyro_arms.mdl",
		"models/weapons/c_models/c_spy_arms.mdl",
		"models/weapons/c_models/c_engineer_arms.mdl"
	};
	
	TFClassType playerClass = TF2_GetPlayerClass(client);
	
	return strcopy(buffer, maxlen, armModels[ view_as<int>(playerClass) ]);
}

void OnAnimationDone(const char[] output, int caller, int activator, float delay)
{
	if(!IsValidClient(activator))
	{
		return;
	}

	float flPlayBackRate = GetEntPropFloat(activator, Prop_Send, "m_flPlaybackRate");
	ViewModel_SetPlaybackRate(activator, flPlayBackRate);
}

void OriginalViewModel_Hide(int client)
{
	if (IsValidEntity(g_iSuperViewModelRef[client]))
	{
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
	}

	return;
}

void ViewModel_SetAnimation(int client, const char[] sAnimation)
{
	if (IsValidEntity(g_iSuperViewModelRef[client]))
	{
		SetVariantString(sAnimation);
		AcceptEntityInput(g_iSuperViewModelRef[client], "SetAnimation");
	}

	return;
}

void ViewModel_SetDefaultAnimation(int client, const char[] sAnimation)
{
	if (IsValidEntity(g_iSuperViewModelRef[client]))
	{
		SetVariantString(sAnimation);
		AcceptEntityInput(g_iSuperViewModelRef[client], "SetDefaultAnimation");
	}

	return;
}

void ViewModel_SetPlaybackRate(int client, const float sPlaybackRate)
{
	if (IsValidEntity(g_iSuperViewModelRef[client]))
	{
		SetVariantFloat(sPlaybackRate);
		AcceptEntityInput(g_iSuperViewModelRef[client], "SetPlaybackRate");
	}

	return;
}

void ViewModel_Destroy(int client)
{
	if (!IsValidClient(client))
	{
		return;
	}
	
	if (IsValidEntity(g_iSuperViewModelRef[client]))
		RemoveEntity(g_iSuperViewModelRef[client]);
	
	g_iSuperViewModelRef[client] = INVALID_ENT_REFERENCE;

	if (IsValidEntity(g_iSuperArmModelRef[client]))
		RemoveEntity(g_iSuperArmModelRef[client]);
	
	g_iSuperArmModelRef[client] = INVALID_ENT_REFERENCE; 

	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);

	return;
}

public Action ViewModel_SetTransmit(int iViewModel, int iClient)
{	
	int iOwner = GetEntPropEnt(iViewModel, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClient(iOwner) || !IsPlayerAlive(iOwner) || iViewModel != EntRefToEntIndex(g_iSuperViewModelRef[iOwner]))
	{
		//Viewmodel entity no longer valid
		ViewModel_Destroy(iOwner);
		return Plugin_Handled;
	}
	
	//Allow if spectating owner and in firstperson
	if (iClient != iOwner)
	{
		if (GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget") == iOwner && GetEntProp(iClient, Prop_Send, "m_iObserverMode") == OBS_MODE_IN_EYE)
		    return Plugin_Continue;
		
		return Plugin_Handled;
	}
	
	//Allow if client itself and in firstperson
	if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting) || GetEntProp(iClient, Prop_Send, "m_nForceTauntCam"))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

stock bool IsValidClient(int client, bool replaycheck=true)
{
	if(client<=0 || client>MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client)))
		return false;

	return true;
}

// dhooks

void DHook_Setup(GameData gamedata)
{
	DHook_CreateDetour(gamedata, "CTFPlayer::DoAnimationEvent", DHook_DoAnimationEventPre);
}

static void DHook_CreateDetour(GameData gamedata, const char[] name, DHookCallback preCallback = INVALID_FUNCTION, DHookCallback postCallback = INVALID_FUNCTION)
{
	DynamicDetour detour = DynamicDetour.FromConf(gamedata, name);
	if(detour)
	{
		if(preCallback!=INVALID_FUNCTION && !DHookEnableDetour(detour, false, preCallback))
			LogError("[Gamedata] Failed to enable pre detour: %s", name);
		
		if(postCallback!=INVALID_FUNCTION && !DHookEnableDetour(detour, true, postCallback))
			LogError("[Gamedata] Failed to enable post detour: %s", name);

		delete detour;
	}
	else
	{
		LogError("[Gamedata] Could not find %s", name);
	}
}

public MRESReturn DHook_DoAnimationEventPre(int client, DHookParam param)
{
	PlayerAnimEvent_t anim = param.Get(1);
	int data = param.Get(2);

	Action action = Weapon_OnAnimation(client, anim, data);
	if(action >= Plugin_Handled)
		return MRES_Supercede;

	if(action == Plugin_Changed)
	{
		param.Set(1, anim);
		param.Set(2, data);
		return MRES_ChangedOverride;
	}

	return MRES_Ignored;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool& result)
{
	char svm[PLATFORM_MAX_PATH];
	if (TF2CustAttr_GetString(weapon, "viewmodel superoverride", svm, sizeof(svm)))
	{
		if(result)
		{
			g_iIsCritAttack[client] = true;
		}
		else
		{
			g_iIsCritAttack[client] = false;
		}
	}
	
	return Plugin_Continue;
}

public Action Weapon_OnAnimation(int client, PlayerAnimEvent_t &anim, int &data)
{
	int weapon = TF2_GetClientActiveWeapon(client);
	if (!IsValidEntity(weapon)) {
		return Plugin_Continue;
	}
	
	char attr[512];
	if(TF2CustAttr_GetString(weapon, "vm superoverride anim", attr, sizeof(attr)))
	{
		if(anim==PLAYERANIMEVENT_ATTACK_PRIMARY || anim==PLAYERANIMEVENT_ATTACK_PRIMARY_SUPER)
		{
			int shouldrandomanim = ReadIntVar(attr, "randomanim", 0);
			char Fire[32];
			if (shouldrandomanim)
			{
				int randomanim = GetRandomInt(0, 2);
				switch(randomanim)
				{
					case 0:
					{
						if(g_iIsCritAttack[client])
						{
							if(ReadStringVar(attr, "fire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
						else
						{
							if(ReadStringVar(attr, "critfire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
					}
					case 1:
					{
						if(g_iIsCritAttack[client])
						{
							if(ReadStringVar(attr, "critfire1", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else if(ReadStringVar(attr, "critfire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
						else
						{
							if(ReadStringVar(attr, "fire1", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else if(ReadStringVar(attr, "fire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
					}
					case 2:
					{
						if(g_iIsCritAttack[client])
						{
							if(ReadStringVar(attr, "critfire2", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else if(ReadStringVar(attr, "critfire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
						else
						{
							if(ReadStringVar(attr, "fire2", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else if(ReadStringVar(attr, "fire", Fire, sizeof(Fire)))
							{
								ViewModel_SetAnimation(client, Fire);
							}
							else
							{
								ViewModel_SetAnimation(client, "fire");
							}
						}
					}
				}
			}
			else
			{
				if(ReadStringVar(attr, "fire", Fire, sizeof(Fire)))
				{
					ViewModel_SetAnimation(client, Fire);
				}
			}

			float flPlayBackRate = GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate");
			ViewModel_SetPlaybackRate(client, flPlayBackRate);

			int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
			HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
		}
		else if(anim==PLAYERANIMEVENT_ATTACK_SECONDARY)
		{
			char AltFire[32];
			if(ReadStringVar(attr, "altfire", AltFire, sizeof(AltFire)))
			{
				ViewModel_SetAnimation(client, AltFire);
				float flPlayBackRate = GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate");
				ViewModel_SetPlaybackRate(client, flPlayBackRate);

				int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
				HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
			}
		}
		else if(anim==PLAYERANIMEVENT_ATTACK_GRENADE)
		{
			char ThrowGrenade[32];
			if(ReadStringVar(attr, "throwgrenade", ThrowGrenade, sizeof(ThrowGrenade)))
			{
				ViewModel_SetAnimation(client, ThrowGrenade);
				float ThrowGrenadePR = ReadFloatVar(attr, "throwgrenadePR", 1.0);
				ViewModel_SetPlaybackRate(client, ThrowGrenadePR);

				int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
				HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
			}
		}
		else if(anim==PLAYERANIMEVENT_RELOAD)
		{
			char Reload[32];
			ReadStringVar(attr, "reload", Reload, sizeof(Reload), "reload");
			ViewModel_SetAnimation(client, Reload);

			float ReloadPR = ReadFloatVar(attr, "reloadPR", 1.0);
			ViewModel_SetPlaybackRate(client, ReloadPR);

			int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
			HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
		}
		else if(anim==PLAYERANIMEVENT_RELOAD_LOOP)
		{
			char ReloadLoop[32];
			ReadStringVar(attr, "reloadloop", ReloadLoop, sizeof(ReloadLoop), "reload_loop");
			ViewModel_SetAnimation(client, ReloadLoop);

			float ReloadLoopPR = ReadFloatVar(attr, "reloadloopPR", 1.0);
			ViewModel_SetPlaybackRate(client, ReloadLoopPR);

			int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
			HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
		}
		else if(anim==PLAYERANIMEVENT_RELOAD_END)
		{
			char ReloadEnd[32];
			ReadStringVar(attr, "reloadend", ReloadEnd, sizeof(ReloadEnd), "reload_end");
			ViewModel_SetAnimation(client, ReloadEnd);

			float ReloadEndPR = ReadFloatVar(attr, "reloadendPR", 1.0);
			ViewModel_SetPlaybackRate(client, ReloadEndPR);

			int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
			HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
		}
	}
	
	return Plugin_Continue;
}

// public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon)
// {
// 	if (!IsValidClient(client)) {
// 		return Plugin_Continue;
// 	}
	
// 	int Weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

// 	if (!IsValidEntity(Weapon)) {
// 		return Plugin_Continue;
// 	}
	
// 	char attr[256];
// 	if(TF2CustAttr_GetString(Weapon, "vm superoverride anim", attr, sizeof(attr)) && IsValidEntity(g_iSuperViewModelRef[client]))
// 	{
// 		if(buttons & IN_ATTACK2)
// 		{
// 			int IsDeadRingerOut = GetEntData(client, FindSendPropInfo("CTFPlayer", "m_bFeignDeathReady"), 1);
// 			if(IsDeadRingerOut)
// 			{	
// 			}
// 			else
// 			{
// 			} 
			
// 			char SpecialFire[32];
// 			if(ReadStringVar(attr, "specialfire", SpecialFire, sizeof(SpecialFire)))
// 			{
// 				ViewModel_SetAnimation(client, SpecialFire);
// 				float SpecialFirePR = ReadFloatVar(attr, "specialfirePR", 1.0);
// 				ViewModel_SetPlaybackRate(client, SpecialFirePR);

// 				int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
// 				HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
// 			}
// 		}
// 		else if(buttons & IN_ATTACK3)
// 		{
// 			char SpecialFire[32];
// 			if(ReadStringVar(attr, "specialfire", SpecialFire, sizeof(SpecialFire)))
// 			{
// 				ViewModel_SetAnimation(client, SpecialFire);
// 				float SpecialFirePR = ReadFloatVar(attr, "specialfirePR", 1.0);
// 				ViewModel_SetPlaybackRate(client, SpecialFirePR);

// 				int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
// 				HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
// 			}
// 		}
// 		else if(buttons & IN_RELOAD)
// 		{
// 			char ReloadButton[32];
// 			if(ReadStringVar(attr, "reloadbutton", ReloadButton, sizeof(ReloadButton)))
// 			{
// 				ViewModel_SetAnimation(client, ReloadButton);
// 				float ReloadButtonPR = ReadFloatVar(attr, "reloadbuttonPR", 1.0);
// 				ViewModel_SetPlaybackRate(client, ReloadButtonPR);

// 				int iViewModel = EntRefToEntIndex(g_iSuperViewModelRef[client]);
// 				HookSingleEntityOutput(iViewModel, "OnAnimationDone", OnAnimationDone, true);
// 			}
// 		}
// 	}
	
// 	return Plugin_Continue;
// }