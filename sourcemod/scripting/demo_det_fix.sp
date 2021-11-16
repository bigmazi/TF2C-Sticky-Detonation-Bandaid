#pragma semicolon 1

#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION "1.2"

public Plugin myinfo = {
	name = "Stickies detonation fix",
	author = "bigmazi",
	description = "Fixes bug when Demoman can't detonate stickies",
	version = PLUGIN_VERSION,
	url = ""
};



// *** Data ***
// -------------------------------------------

#define SBL_INDEX 20
#define ARM_TIME 0.8

enum Field {
	m_ent,
	m_owner,
	m_armTimeOverStamp,
	FIELDS_COUNT
};

#define PLAYERS_ARRAY_SIZE (MAXPLAYERS + 1)
#define ENTS_ARRAY_SIZE 2049

#define ARENA_SIZE 192 // 64 players having 3 unarmed stickybombs - will never happen, but just in case

int g_entDataArena[ARENA_SIZE][view_as<int>(FIELDS_COUNT)];
#define ARENA_FREE_PTR g_ptr[0]

int g_ptr[ENTS_ARRAY_SIZE];
bool g_mustForbidAltfire[PLAYERS_ARRAY_SIZE];



// *** Creation/Destruction ***
// -------------------------------------------

public OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_projectile_pipe_remote"))
	{
		SDKHook(entity, SDKHook_Spawn, Hook_StickySpawned);
	}
}

void Hook_StickySpawned(int e)
{
	int owner = GetEntPropEnt(e, Prop_Send, "m_hOwnerEntity");	
	if (!IsValidClient(owner)) return;
	
	int sbl = HasSbl(owner);
	
	if (!sbl || !LaunchedByWep(e, sbl)) return;
	
	g_entDataArena[ARENA_FREE_PTR][m_ent] = e;
	g_entDataArena[ARENA_FREE_PTR][m_owner] = owner;
	g_entDataArena[ARENA_FREE_PTR][m_armTimeOverStamp] = view_as<int>(GetGameTime() + ARM_TIME);
	
	ARENA_FREE_PTR += 1;
	g_ptr[e] = ARENA_FREE_PTR;
}

public OnEntityDestroyed(int e)
{
	if (e < 1) return;
	
	int ptr = g_ptr[e];
	
	if (ptr)
	{
		Deallocate(e, ptr);
	}
}

void Deallocate(int e, int ptr)
{
	ptr -= 1;
	g_ptr[e] = 0;
	ARENA_FREE_PTR -= 1;
	
	for (int i = ptr; i < ARENA_FREE_PTR; ++i)
	{
		g_entDataArena[i][m_ent] = g_entDataArena[i + 1][m_ent];
		g_entDataArena[i][m_owner] = g_entDataArena[i + 1][m_owner];
		g_entDataArena[i][m_armTimeOverStamp] = g_entDataArena[i + 1][m_armTimeOverStamp];
		
		g_ptr[g_entDataArena[i][m_ent]] -= 1;
	}	
}



// *** Per-frame logic ***
// -------------------------------------------

public OnGameFrame()
{
	float now = GetGameTime();
	
	for (int i = 0; i < ARENA_FREE_PTR; ++i)
	{		
		float armTimeOverStamp = view_as<float>(g_entDataArena[i][m_armTimeOverStamp]);
		
		if (now > armTimeOverStamp)
		{
			int owner = g_entDataArena[i][m_owner];
			g_mustForbidAltfire[owner] = true;
			
			int e = g_entDataArena[i][m_ent];
			int ptr = g_ptr[e];
			Deallocate(e, ptr);
			i -= 1;
		}
	}
}

public Action OnPlayerRunCmd(
		int c, int& btns, int& impulse, 
		float vel[3], float angles[3],		
		int& weapon, int& subtype, int& cmdnum, 
		int& tickcount, int& seed, int mouse[2])
{
	if (g_mustForbidAltfire[c])
	{		
		g_mustForbidAltfire[c] = false;
		
		if (!SblActive(c))
		{
			btns &= ~IN_ATTACK2;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}



// *** Utils ***
// -------------------------------------------

bool IsValidClient(int e)
{
	return e > 0 && e <= MaxClients && IsClientInGame(e);
}

int HasSbl(int c)
{
	int secondary = GetPlayerWeaponSlot(c, 1);
	
	return IsValidEntity(secondary) && GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex") == SBL_INDEX
		? secondary
		: 0;
}

bool SblActive(int c)
{
	int secondary = GetPlayerWeaponSlot(c, 1);
	
	return IsValidEntity(secondary)
		&& GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex") == SBL_INDEX
		&& secondary == GetEntPropEnt(c, Prop_Send, "m_hActiveWeapon");
}

bool LaunchedByWep(int sticky, int wep)
{
	return GetEntPropEnt(sticky, Prop_Send, "m_hLauncher") == wep;
}