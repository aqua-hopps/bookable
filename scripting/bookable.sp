#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>
#include <steampawn>
#include <dbi>

#define DATABASE_LENGTH	16
#define REGION_LENGTH 4
#define HOSTNAME_LENGTH 48
#define PASSWORD_LENGTH 8
#define IP_LENGTH 24

public Plugin myinfo =
{
	name = "AsiaFortress Bookable",
	author = "aqua_hopps",
	description = "My first plugin ever",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

char g_database[DATABASE_LENGTH];
char g_region[REGION_LENGTH];
char g_serverName[HOSTNAME_LENGTH];
char g_serverPassword[PASSWORD_LENGTH + 1];
char g_rconPassword[PASSWORD_LENGTH + 1];
char g_publicIP[IP_LENGTH];
char g_fakeIP[IP_LENGTH];
int g_publicPort;
int g_fakePort;
int g_tvPort;
int g_regionid;

ConVar g_cvar_database;
ConVar g_cvar_region;
ConVar g_cvar_regionid;
ConVar g_cvar_serverPassword;
ConVar g_cvar_rconPassword;

Database booking;

public void OnPluginStart(){
	RegAdminCmd("sm_send", Command_Send, ADMFLAG_GENERIC, "Send everything.");
	RegAdminCmd("sm_getinfo", Command_GetInfo, ADMFLAG_GENERIC, "Get all server information.");
	RegConsoleCmd("sm_info", Command_Info, "Get server information.");

	// Create ConVars
	g_cvar_database = CreateConVar("sm_bookable_database", "", "Set the database keyname.");
	g_cvar_region = CreateConVar("sm_bookable_region", "", "Set the server region name.");
	g_cvar_regionid = CreateConVar("sm_bookable_regionid", "", "Set the server region id.");
	g_cvar_serverPassword = FindConVar("sv_password");
	g_cvar_rconPassword = FindConVar("rcon_password");

	// Set ConVar values
	GetConVarString(g_cvar_database, g_database, sizeof(g_database));
	GetConVarString(g_cvar_region, g_region, sizeof(g_region));
	g_regionid = GetConVarInt(g_cvar_regionid);

	// Set random passwords
	GetRandomString(g_serverPassword, PASSWORD_LENGTH);
	GetRandomString(g_rconPassword, PASSWORD_LENGTH);
	SetConVarString(FindConVar("sv_password"), g_serverPassword);
	SetConVarString(FindConVar("rcon_password"), g_rconPassword);

	// Set ConVar Hooks
	HookConVarChange(g_cvar_serverPassword, OnServerPasswordChanged);
	HookConVarChange(g_cvar_rconPassword, OnRconPasswordChanged);
	HookConVarChange(g_cvar_region, OnRegionChanged);
	HookConVarChange(g_cvar_regionid, OnRegionIDChanged);

	// Get server info
	GetConVarString(FindConVar("hostname"), g_serverName, HOSTNAME_LENGTH);
	g_publicPort = GetConVarInt(FindConVar("hostport"));
	g_tvPort = GetConVarInt(FindConVar("tv_port"));
	g_fakePort = SteamPawn_GetSDRFakePort(0);
	GetFakeIP();
	GetPublicIP();

	ConnectToDatabase();
	SendServerInfo();
}
 
public void OnMapStart(){
	GetFakeIP();
	GetPublicIP();
}

public Action Command_GetInfo(int client, int args){
	// Output plugin information
	PrintToChat(client,"Name: 		%s",	g_serverName);
	PrintToChat(client,"SDR: 		%s:%d",	g_fakeIP, g_fakePort);
	PrintToChat(client,"SDR STV: 	%s:%d",	g_fakeIP, g_fakePort + 1);
	PrintToChat(client,"Non-SDR: 	%s:%d",	g_publicIP, g_publicPort);
	PrintToChat(client,"STV: 		%s:%d",	g_publicIP, g_tvPort);
	PrintToChat(client,"Password: 	%s",	g_serverPassword);
	PrintToChat(client,"RCON: 		%s",	g_rconPassword);	
	return Plugin_Handled;
}

public Action Command_Info(int client, int args){
	// Output plugin information
	PrintToChatAll("Name: 		%s",	g_serverName);
	PrintToChatAll("SDR: 		%s:%d",	g_fakeIP, g_fakePort);
	PrintToChatAll("Non-SDR: 	%s:%d",	g_publicIP, g_publicPort);
	PrintToChatAll("STV: 		%s:%d",	g_publicIP, g_tvPort);
	PrintToChatAll("Password: 	%s",	g_serverPassword);	
	return Plugin_Handled;
}

public Action Command_Send(int client, int args){
	SendServerInfo();
	return Plugin_Handled;
}

public void OnServerPasswordChanged(ConVar convar, const char[] oldValue, const char[] newValue){
	strcopy(g_serverPassword, sizeof(g_serverPassword), newValue);

	char query[512];
	Format(query, sizeof(query),
	"UPDATE								\
		ServerInfo						\
	SET									\
		sv_password		=	'%s'		\
	WHERE								\
		Region			=	'%s'		\
	AND									\
		region_serverid = 	 %d;"	,	\
	g_serverPassword, g_region, g_regionid);
}

public void OnRconPasswordChanged(ConVar convar, const char[] oldValue, const char[] newValue){
	strcopy(g_serverPassword, sizeof(g_serverPassword), newValue);

	char query[512];
	Format(query, sizeof(query),
	"UPDATE								\
		ServerInfo						\
	SET									\
		rcon_password	=	'%s'		\
	WHERE								\
		Region			=	'%s'		\
	AND									\
		region_serverid = 	 %d;"	,	\
	g_rconPassword, g_region, g_regionid);
}

public void OnRegionChanged(ConVar convar, const char[] oldValue, const char[] newValue){
	strcopy(g_region, sizeof(g_region), newValue);
}

public void OnRegionIDChanged(ConVar convar, const char[] oldValue, const char[] newValue){
	g_regionid = GetConVarInt(convar);
}

void SendServerInfo(){
	char query[512];
	if(strlen(g_region) && g_regionid){
		// TODO: hostname causes SQL Injection
		Format(query, sizeof(query),		
		"UPDATE								\
			ServerInfo						\
		SET									\
			sv_password		=	'%s',		\
			`Server IP`		=	'%s',		\
			`Server Port`	=	 %d ,		\
			`SourceTV port`	=	 %d ,		\
			`SDR IP`		=	'%s',		\
			`SDR Port`		=	 %d ,		\
			rcon_password	=	'%s'		\
		WHERE								\
			Region			=	'%s'		\
		AND									\
			region_serverid = 	 %d;"	,	\
		g_serverPassword, g_publicIP, g_publicPort, g_tvPort,	\
		g_fakeIP, g_fakePort, g_rconPassword, g_region, g_regionid);

		if(SQL_Query(booking, query) == INVALID_HANDLE){
			SQL_GetError(booking, query, sizeof(query));
			PrintToServer("Could not send server info: %s", query);
		}
		else{
			PrintToServer("Sent server info to databse.");
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

void GetFakeIP(){
    int ip = SteamPawn_GetSDRFakeIP();
    int octet1 = (ip >> 24) & 255;
    int octet2 = (ip >> 16) & 255;
    int octet3 = (ip >> 8) & 255;
    int octet4 = ip & 255;
    Format(g_fakeIP, IP_LENGTH, "%d.%d.%d.%d", octet1, octet2, octet3, octet4);
}

void GetPublicIP(){
    int ipaddr[4];
    SteamWorks_GetPublicIP(ipaddr);
    Format(g_publicIP, IP_LENGTH, "%d.%d.%d.%d", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

// Generate a random password
void GetRandomString(char[] buffer, int len)
{
    static char listOfChar[] = "abcdefghijklmnopqrstuvwxyz0123456789";

    for (int i = 0; i <= len; i++)
    {
        // Using GetURandomInt is "safer" for random number generation
        buffer[i] = listOfChar[GetURandomInt() % (sizeof(listOfChar) - 1)];
    }

    // Strings need to be null-terminated
    buffer[len] = '\0';
}
