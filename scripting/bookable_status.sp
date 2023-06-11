#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "avan"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <dbi>

#pragma newdecls required

#define DATABASE_LENGTH    16
#define REGION_LENGTH 4
#define MAX_AFK_PLAYERS 0

char g_database[DATABASE_LENGTH];
char g_region[REGION_LENGTH];

int g_regionid;
int g_playercounts = 0;

ConVar g_cvar_database;
ConVar g_cvar_region;
ConVar g_cvar_regionid;

Database booking;
Handle emptyTimer;


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
    
    GetConVarString(g_cvar_database, g_database, sizeof(g_database));
    GetConVarString(g_cvar_region, g_region, sizeof(g_region));
    g_regionid = GetConVarInt(g_cvar_regionid);
    
    ConnectToDatabase();
    CountPlayers();
}

public void OnClientConnected(){
    //CreateTimer(2.0, EmptyTimer, _);
    g_playercounts++;
    SetEmptyTimer();
}

public void OnClientDisconnect(){
    //CreateTimer(2.0, EmptyTimer, _);
    g_playercounts--;
    SetEmptyTimer();
}

void SetEmptyTimer()
{
    if (emptyTimer == INVALID_HANDLE){
        if (g_playercounts <= MAX_AFK_PLAYERS){
            emptyTimer = CreateTimer(10.0, UnBook, _);
            PrintToServer("Timer Starting");
        }
        else{
            PrintToServer("Timer '%d' already active", emptyTimer);
        }
    }
    else if (g_playercounts > MAX_AFK_PLAYERS) {
        CloseHandle(emptyTimer);
        emptyTimer = null;
        PrintToServer("Enough Players, Timer deleted");
    }
}


public Action UnBook(Handle timer){
    PrintToServer("HAHA");
    emptyTimer = null;
    return Plugin_Stop;
}

void CountPlayers(){
    
    for (int client = 1 ; client <= MaxClients; client++)
    {       
        if (IsClientInGame(client))
            if (!IsFakeClient(client))
                g_playercounts++;
    }
    PrintToServer("Human player count %i", g_playercounts);
    SetEmptyTimer();
}

void SendEmptyInfo(){
    char query[512];
    if(strlen(g_region) && g_regionid){
        Format(query, sizeof(query),        
        "UPDATE                                \
            ServerInfo                        \
        SET                                    \
            'Empty'         =    1            \
        WHERE                                \
            Region            =    '%s'        \
        AND                                    \
            region_serverid =      %d;"    ,    \
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
