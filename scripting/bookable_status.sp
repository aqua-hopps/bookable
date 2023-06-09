#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "avan"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <dbi>

#pragma newdecls required

#define DATABASE_LENGTH	16
#define REGION_LENGTH 4

char g_database[DATABASE_LENGTH];
char g_region[REGION_LENGTH];

int g_regionid;
int g_playercounts;

float g_emptyInfoTime = 0.0;

ConVar g_cvar_database;
ConVar g_cvar_region;
ConVar g_cvar_regionid;

Database booking;


public Plugin myinfo = 
{
	name = "AsiaFortress Server Status",
	author = PLUGIN_AUTHOR,
	description = "Update Server Status",
	version = PLUGIN_VERSION,
	url = "None"
};


public void OnPluginStart()
{
	g_cvar_database = CreateConVar("sm_bookable_database", "", "Set the database keyname.");
	g_cvar_region = CreateConVar("sm_bookable_region", "", "Set the server region name.");
	g_cvar_regionid = CreateConVar("sm_bookable_regionid", "", "Set the server region id.");
	
	GetConVarString(g_cvar_database, g_database, sizeof(g_region));
	GetConVarString(g_cvar_region, g_region, sizeof(g_region));
	g_regionid = GetConVarInt(g_cvar_regionid);
	
	ConnectToDatabase();
}

public void OnClientConnected(){
	CreateTimer(2.0, EmptyTimer, _);
}

public void OnClientDisconnect(){
	CreateTimer(2.0, EmptyTimer, _);
}

public Action EmptyTimer(Handle timer){
	
	g_playercounts = 0;
	
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        
        if (IsFakeClient(client)) continue;

        g_playercounts++;
    }

    PrintToServer("Human player count %i", g_playercounts);
    
    if (g_playercounts < 1)
    {

        g_emptyInfoTime += GetGameFrameTime();
        
        if (g_emptyInfoTime >= 30.0)
        {
            SendEmptyInfo();
            g_emptyInfoTime = 0.0;
        }
    }
    else
    {
        g_emptyInfoTime = 0.0;
    }
    
    return Plugin_Continue;
}


void SendEmptyInfo(){
	char query[512];
	if(strlen(g_region) && g_regionid){
		Format(query, sizeof(query),		
		"UPDATE								\
			ServerInfo						\
		SET									\
			'Empty'     	=	1		    \
		WHERE								\
			Region			=	'%s'        \
		AND									\
			region_serverid = 	 %d;"	,	\
		g_region, g_regionid);

		if(SQL_Query(booking, query) == INVALID_HANDLE){
			SQL_GetError(booking, query, sizeof(query));
			PrintToServer("Could not send Empty Status: %s", query);
		}
		else{
			PrintToServer("Sent Empty Status to database.");
		}
	}
}

void ConnectToDatabase(){
	char error[512];
	booking = SQL_Connect(g_database, true, error, sizeof(error));
	if(booking)
		PrintToServer("Connected to database.");
	else
		PrintToServer("Could not connect to database: %s", error);
}
