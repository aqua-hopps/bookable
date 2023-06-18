#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>
#include <dbi>

#define NAME_LENGTH 16
#define IP_LENGTH 16
#define PASSWORD_LENGTH 8

#define MAX_AFK_PLAYERS 2
#define MAX_AFK_TIME 600.0

public Plugin myinfo =
{
	name = "AsiaFortress Bookable",
	author = "aqua-hopps & avanavan",
	description = "A plugin for sending server info to a database.",
	version = "1.11",
	url = "https://github.com/aqua-hopps/asiafortress-bookable"
};

char g_dbName[NAME_LENGTH];
char g_instanceName[NAME_LENGTH];

char g_serverPassword[PASSWORD_LENGTH + 1];
char g_rconPassword[PASSWORD_LENGTH + 1];

char g_publicIP[16];
char g_fakeIP[16];

int g_publicPort;
int g_fakePort;
int g_tvPort;
int g_playerCount = 0;

Address g_adrFakeIP;
Address g_adrFakePorts;

ConVar g_cvarDBName;
ConVar g_cvarServerPassword;
ConVar g_cvarRconPassword;

Handle g_hGameConf;
Handle g_hAFKTimer;


public void OnPluginStart(){
	RegAdminCmd("sm_send", Command_Send, ADMFLAG_GENERIC, "Send all server information.");
	RegAdminCmd("sm_getinfo", Command_GetInfo, ADMFLAG_GENERIC, "Print all server information.");
	RegConsoleCmd("sm_info", Command_Info, "Print server information.");
	RegConsoleCmd("sm_stv", Command_STV, "Print stv information.");
	RegConsoleCmd("sm_generate", Command_Generate, "Generate new passwords for the server.");

	// Create ConVars
	g_cvarDBName = CreateConVar("sm_bookable_database", "", "Set the database keyname.");
	g_cvarServerPassword = FindConVar("sv_password");
	g_cvarRconPassword = FindConVar("rcon_password");

	// Set random passwords
	GetRandomString(g_serverPassword, PASSWORD_LENGTH);
	GetRandomString(g_rconPassword, PASSWORD_LENGTH);
	g_cvarServerPassword.SetString(g_serverPassword);
	g_cvarRconPassword.SetString(g_rconPassword);

	// Set ConVar Hooks
	HookConVarChange(g_cvarDBName, OnDatabaseChanged);

	// Load gamedata
	g_hGameConf = LoadGameConfigFile("bookable");

	// Get addresses for engine variables
	g_adrFakeIP = GameConfGetAddress(g_hGameConf, "g_nFakeIP");
	g_adrFakePorts = GameConfGetAddress(g_hGameConf, "g_arFakePorts");

	// Get server information
	g_cvarDBName.GetString(g_dbName, sizeof(g_dbName));
	g_publicPort = GetConVarInt(FindConVar("hostport"));
	g_tvPort = GetConVarInt(FindConVar("tv_port"));
	g_fakePort = GetFakePort(0);
	GetPublicIP(g_publicIP, sizeof(g_publicIP));
	GetFakeIP(g_fakeIP, sizeof(g_fakeIP));

	// Check if database name is valid
	if (!SQL_CheckConfig(g_dbName)){
		LogError("Could not locate \"%s\" in databases.cfg.", g_dbName);
	}
	else {
		Database.Connect(SendServerInfoAll, g_dbName, _);
	}

	// Count players
	for (int i = 1 ; i <= MaxClients; i++)
    {       
        if (IsClientInGame(i) && !IsFakeClient(i)){
            g_playerCount++;
		}
    }
	SetAFKTimer();
}

public void OnMapStart(){
	Database.Connect(SendServerInfoAll, g_dbName, _);
}

public void OnClientConnected(){
    g_playerCount++;
    SetAFKTimer();
}

public void OnClientDisconnect(){
    g_playerCount--;
    SetAFKTimer();
}

public void OnDatabaseChanged(ConVar convar, const char[] oldValue, const char[] newValue){
	strcopy(g_dbName, sizeof(g_dbName), newValue);
	if (!SQL_CheckConfig(g_dbName)){
		LogError("Could not locate \"%s\" in the database config.", g_dbName);
	}
	else {
		Database.Connect(SendServerInfoAll, g_dbName, _);
	}
}

public Action Command_Send(int client, int args){
	Database.Connect(SendServerInfoAll, g_dbName, _);
	PrintToChat(client, "Manually sent server info to database.");
	return Plugin_Handled;
}

public Action Command_GetInfo(int client, int args){
	// Output plugin information
	PrintToChat(client,"SDR IP:		%s:%d",	g_fakeIP, g_fakePort);
	PrintToChat(client,"SDR STV:	%s:%d",	g_fakeIP, g_fakePort + 1);
	PrintToChat(client,"IP:			%s:%d",	g_publicIP, g_publicPort);
	PrintToChat(client,"STV:		%s:%d",	g_publicIP, g_tvPort);
	PrintToChat(client,"Password:	%s",	g_serverPassword);
	PrintToChat(client,"RCON:		%s",	g_rconPassword);	
	return Plugin_Handled;
}

public Action Command_Info(int client, int args){
	// Output plugin information
	PrintToChatAll("SDR IP:		%s:%d",	g_fakeIP, g_fakePort);
	PrintToChatAll("Non-SDR:	%s:%d",	g_publicIP, g_publicPort);
	PrintToChatAll("Password:	%s",	g_serverPassword);	
	return Plugin_Handled;
}

public Action Command_STV(int client, int args){
	// Output plugin information
	PrintToChatAll("SDR STV:	%s:%d",	g_fakeIP, g_fakePort + 1);
	PrintToChatAll("Non-SDR:	%s:%d",	g_publicIP, g_tvPort);
	return Plugin_Handled;
}

public Action Command_Generate(int client, int args){

	// Get random passwords
	GetRandomString(g_serverPassword, PASSWORD_LENGTH);
	GetRandomString(g_rconPassword, PASSWORD_LENGTH);

	// Set server passwords
	g_cvarServerPassword.SetString(g_serverPassword);
	g_cvarRconPassword.SetString(g_rconPassword);

	Database.Connect(SendServerPasswords, g_dbName, _);

	PrintToChatAll("New Password: %s", g_serverPassword);

	return Plugin_Handled;
}

public Action OnServerEmpty(Handle timer){
	Database.Connect(SendServerInfoEmpty, g_dbName, _);
	g_hAFKTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

public void SendServerPasswords(Database db, const char[] error, any data){
	if (db == null){
        LogError("Could not connect to the database: %s", error);
    }
	else{
		char buffer[256];
		if (g_instanceName[0] == '\0'){
			db.Format(buffer, sizeof(buffer),
				"UPDATE ServerInfo				\
				SET								\
					`sv_password` 	= '%s'	,	\
					`rcon_password` = '%s'		\
				WHERE							\
					`Server IP` 	= '%s'		\
				AND								\
					`Server Port`	=  %d	;",	\
				g_serverPassword, g_rconPassword, g_publicIP, g_publicPort);
		}
		else {
			db.Format(buffer, sizeof(buffer),
				"UPDATE ServerInfo				\
				SET								\
					`sv_password` 	= '%s'	,	\
					`rcon_password` = '%s'		\
				WHERE							\
					`instance_name`	= '%s'	;",	\
				g_serverPassword, g_rconPassword, g_instanceName);
		}
		db.Query(T_SendServerInfo, buffer, _);
	}
}

public void SendServerInfoAll(Database db, const char[] error, any data){
	if (db == null){
        LogError("Could not connect to the database: %s", error);
    }
	else{
		// Check if the server is an VM Instance
		char buffer[256];
		db.Format(buffer, sizeof(buffer), "SELECT instance_name FROM ServerInfo WHERE `Server IP` = '%s';", g_publicIP);
		db.Query(T_SendServerInfoAll, buffer, _);
	}
}

public void SendServerInfoEmpty(Database db, const char[] error, any data){
	if (db == null){
		LogError("Could not connect to the database: %s", error);
	}
	else{
		char buffer[256];
		if (g_instanceName[0] == '\0'){
			db.Format(buffer, sizeof(buffer), "UPDATE ServerInfo SET `Empty` = 1	\
				WHERE `Server IP` = '%s' AND `Server Port` = '%d' ;", g_publicIP, g_publicPort);
		}
		else {
			db.Format(buffer, sizeof(buffer), "UPDATE ServerInfo SET `Empty` = 1 WHERE `instance_name` = '%s' ;", g_instanceName);
		}
		db.Query(T_SendServerInfo, buffer, _);
	}
}

public void T_SendServerInfo(Database db, DBResultSet results, const char[] error, any data){
	if (db == null || results == null || error[0] != '\0'){
		LogError("Could not send server info to the database: %s", error);
	}
	else if (results.AffectedRows > 1){
		ThrowError("This server has multiple entries in the database.");
	}
}

public void T_SendServerInfoAll(Database db, DBResultSet results, const char[] error, any data){
	if (db == null || results == null || error[0] != '\0'){
        LogError("Could not query the database: %s", error);
    }
	else if (results.RowCount == 0){
		LogError("This server has no entry in the database.");
	}
	else if (results.RowCount >= 1){
		char buffer[512];
		results.FetchRow();

		if(results.IsFieldNull(0)){
			g_instanceName[0] = '\0';
		}
		else{
			results.FetchString(0, g_instanceName, sizeof(g_instanceName));
		}

		if (g_instanceName[0] == '\0'){
			db.Format(buffer, sizeof(buffer),
				"UPDATE	ServerInfo					\
				SET									\
					`sv_password`	=	'%s'	,	\
					`rcon_password`	=	'%s'	,	\
					`SDR IP`		=	'%s'	,	\
					`SDR Port`		=	 %d		,	\
					`SourceTV port`	=	 %d			\
				WHERE								\
					`Server IP``	=	'%s'		\
				AND									\
					`Server Port`	=	 %d		;",	\
				g_serverPassword, g_rconPassword, g_fakeIP, g_fakePort, g_tvPort, g_publicIP, g_publicPort);
		}
		else{
			db.Format(buffer, sizeof(buffer),
				"UPDATE	ServerInfo					\
				SET									\
					`sv_password`	=	'%s'	,	\
					`rcon_password`	=	'%s'	,	\
					`SDR IP`		=	'%s'	,	\
					`SDR Port`		=	 %d		,	\
					`Server Port`	=	 %d		,	\
					`SourceTV port`	=	 %d			\
				WHERE								\
					`instance_name` = 	'%s'	;",	\
				g_serverPassword, g_rconPassword, g_fakeIP, g_fakePort, g_publicPort, g_tvPort, g_instanceName);
		}
		db.Query(T_SendServerInfo, buffer, _);
	}
}

// Generate a random password
void GetRandomString(char[] buffer, int len){
	static char charList[] = "abcdefghijklmnopqrstuvwxyz0123456789";
	
	for (int i = 0; i <= len; i++){
		// Using GetURandomInt is "safer" for random number generation
		buffer[i] = charList[GetURandomInt() % (sizeof(charList) - 1)];
    }

	// Strings need to be null-terminated
	buffer[len] = '\0';
}

void SetAFKTimer(){
    if (g_playerCount < MAX_AFK_PLAYERS && g_hAFKTimer == INVALID_HANDLE){
		// Start AFK timer when playercount is less or equal to the MAX_AFK_PLAYERS
        g_hAFKTimer = CreateTimer(MAX_AFK_TIME, OnServerEmpty, _);
    }
    if (g_playerCount >= MAX_AFK_PLAYERS && g_hAFKTimer != INVALID_HANDLE){
		// Delete timer when playercount exceeds MAX_AFK_PLAYERS
        CloseHandle(g_hAFKTimer);
        g_hAFKTimer = INVALID_HANDLE;
    }
}

void GetPublicIP(char[] buffer, int size){
	int ipaddr[4];

	SteamWorks_GetPublicIP(ipaddr);
	Format(buffer, size, "%d.%d.%d.%d", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

void GetFakeIP(char[] buffer, int size){
	if (!g_adrFakeIP) {
		buffer[0] = '\0';
	}
	int ipaddr = LoadFromAddress(g_adrFakeIP, NumberType_Int32);

	int octet1 = (ipaddr >> 24) & 255;
	int octet2 = (ipaddr >> 16) & 255;
	int octet3 = (ipaddr >> 8) & 255;
	int octet4 = ipaddr & 255;

	Format(buffer, size, "%d.%d.%d.%d", octet1, octet2, octet3, octet4);
}

int GetFakePort(int num) {
	if (!g_adrFakePorts || num < 0 || num >= 2){
		return 0;
	}

	return LoadFromAddress(g_adrFakePorts + (num * 0x2), NumberType_Int16);
}
