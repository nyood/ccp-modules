#pragma newdecls required

#define INCLUDE_RIPJSON

#include <ccprocessor>
#include <shop>
#include <ccprocessor_pkg>

#define SZ(%0) %0, sizeof(%0)

public Plugin myinfo = 
{
	name = "[CCP] Custom Chat <SHOP>",
	author = "nullent?",
	description = "...",
	version = "1.6.0",
	url = "discord.gg/ChTyPUG"
};

const ItemType g_IType = Item_Togglable;

static const char pkgKey[] = "shop_chat";

int levels[BIND_MAX];

bool g_bLate;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_bLate = late;
    return APLRes_Success;
}

public void OnPluginStart()
{    
    LoadTranslations("ccp_core.phrases");
    LoadTranslations("ccp_shop.phrases");

    manageConVars();
}

void manageConVars(bool bCreate = true) {
    char szBuffer[128];

    for(int i; i < BIND_MAX; i++) {
        FormatBind("ccp_shop_", i, 'l', szBuffer, sizeof(szBuffer)/2);
        if(bCreate){
            Format(szBuffer[strlen(szBuffer)+1], sizeof(szBuffer), "Priority level for %s", szBinds[i]);
            CreateConVar(szBuffer, "1", szBuffer[strlen(szBuffer)+1], _, true, 1.0).AddChangeHook(onChange);
        } else {
            onChange(FindConVar(szBuffer), NULL_STRING, NULL_STRING);
        }
    }
    
    if(bCreate) {
        AutoExecConfig(true, "ccp_shopchat", "ccprocessor");
    }
}

public void onChange(ConVar convar, const char[] oldVal, const char[] newVal)
{
    char szBuffer[64];
    convar.GetName(szBuffer, sizeof(szBuffer));

    int part = BindFromString(szBuffer);
    if(part == BIND_MAX)
        return;
    
    levels[part] = convar.IntValue;
}

public void ccp_OnPackageAvailable(int iClient, Handle jsonObj) {
    static const char cloud[]           = "cloud";
    static char config[MESSAGE_LENGTH]  = "configs/shop/ccprocessor/shop_chat.json";

    JSONObject objPackage = asJSONO(jsonObj);

    if(!objPackage) {
        return;
    }

    // Loaded from cloud
    if(objPackage.HasKey(pkgKey) && objPackage.HasKey(cloud) && objPackage.GetBool(cloud)) {
        return;
    }

    JSONObject objData;

    if(!iClient) {
        // Load from local
        if(config[0] == 'c') {
            BuildPath(Path_SM, config, sizeof(config), config);
        } 
        
        if(!FileExists(config)) {
            SetFailState("Config file is not exists: %s", config);
        }

        objData = JSONObject.FromFile(config, 0);
    }

    if(!objData) {
        objData = new JSONObject();
    }

    objPackage.Set(pkgKey, objData);

    delete objData;
}

public void OnMapStart() {
    // Handshake
    cc_proc_APIHandShake(cc_get_APIKey());

    manageConVars(false);

    // late load
    if(g_bLate) {
        g_bLate = false;

        for(int i; i <= MaxClients; i++) {
            if(!i || (IsClientInGame(i) && !IsFakeClient(i) && IsClientAuthorized(i))) {
                ccp_OnPackageAvailable(i, ccp_GetPackage(i));
            }
        }
    }

    if(Shop_IsStarted()) {
        Shop_Started();
    }
}

public void Shop_Started()
{
    OnMapEnd();
    RegisterCategorys();
}

public void OnMapEnd()
{
    Shop_UnregisterMe();
}

public void OnPluginEnd()
{
    OnMapEnd();
}

void RegisterCategorys() {
    JSONObject obj = asJSONO(asJSONO(ccp_GetPackage(0)).Get(pkgKey));
    if(!obj) {
        return;
    }

    JSONArray jsonPart;
    JSONObject item;

    CategoryId id;

    for(int i; i < BIND_MAX; i++ ) {
        if(!obj.HasKey(szBinds[i])) {
            continue;
        }

        jsonPart = asJSONA(obj.Get(szBinds[i]));
        if(!jsonPart || !jsonPart.Length) {
            delete jsonPart;
            continue;
        }

        id = Shop_RegisterCategory(
            szBinds[i], szBinds[i], NULL_STRING, OnCategoryDisplayed
        );

        if(id == INVALID_CATEGORY) {
            delete jsonPart;
            continue;
        }

        for(int j; j < jsonPart.Length; j++) {
            if((item = asJSONO(jsonPart.Get(j)))) {
                RegisterItem(id, item);
            }

            delete item;
        }

        delete jsonPart;
    }
    
    delete obj;
}

void RegisterItem(CategoryId cid, JSONObject item)
{
    char szBuffer[NAME_LENGTH];
    item.GetString("value", szBuffer, sizeof(szBuffer));

    if(Shop_StartItem(cid, szBuffer))
    {
        Shop_SetInfo(szBuffer, NULL_STRING, item.GetInt("price"), item.GetInt("sellprice"), g_IType, item.GetInt("duration"));
        Shop_SetCallbacks(OnItemRegistered, OnItemToogle, _, OnItemDisplay, _, _, OnItemBuy, OnItemSell);
            
        Shop_EndItem();
    }
}

public void OnItemRegistered(CategoryId category_id, const char[] category, const char[] item, ItemId item_id)
{
    // ...
}

public ShopAction OnItemToogle(int iClient, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
    int part = BindFromString(category);

    char szValue[MESSAGE_LENGTH];

    // value of client model
    JSONObject obj = getClientModel(iClient);
    if(obj && IsPartValid(obj, part)) {
        obj.GetString(szBinds[part], szValue, sizeof(szValue));
    }

    if(!obj)
        obj = new JSONObject();

    if(szValue[0])
    {
        if(!StrEqual(item, szValue))
            Shop_ToggleClientItem(iClient, Shop_GetItemId(category_id, szValue), Toggle_Off);

        szValue = NULL_STRING;
    }

    if(!(isOn || elapsed))
        strcopy(szValue, sizeof(szValue), item);
    
    if(szValue[0]) {
        obj.SetString(szBinds[part], szValue);
    } else obj.SetNull(szBinds[part]);

    asJSONO(ccp_GetPackage(iClient)).Set(pkgKey, obj);
    delete obj;

    return (isOn || elapsed) ? Shop_UseOff : Shop_UseOn;
}

public bool OnItemDisplay(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, ShopMenu menu, bool &disabled, const char[] name, char[] buffer, int maxlen)
{
    int part = BindFromString(category);

    FormatEx(buffer, maxlen, "%T", name, client);

    ccp_replaceColors(buffer, true);

    if(part == BIND_PREFIX)
        Format(buffer, maxlen, "%T", "tag_display", client, buffer);

    return true;
}

public bool OnCategoryDisplayed(int client, CategoryId category_id, const char[] category, const char[] name, char[] buffer, int maxlen, ShopMenu menu)
{
    FormatEx(buffer, maxlen, "%T", name, client);
    return true;
}

public bool OnItemBuy(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, ItemType type, int price, int sell_price, int value) {
    JSONObject clientObject = asJSONO(ccp_GetPackage(client));
    JSONObject serverModel = getClientModel(0);

    bool stop = !serverModel || (!clientObject.HasKey("auth") && serverModel.GetBool("secure"));

    delete serverModel;

    if(stop)
        PrintToChat(client, "%T", "secure_restriction", client);

    return !stop;  
}

public bool OnItemSell(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, ItemType type, int sell_price)
{
    JSONObject obj = asJSONO(ccp_GetPackage(client));
    JSONObject serverModel = getClientModel(0);

    if(!serverModel || (!obj.HasKey("auth") && serverModel.GetBool("secure"))) {
        delete serverModel;

        PrintToChat(client, "%T", "secure_restriction", client);
        return false;
    }

    delete serverModel;

    int part = BindFromString(category);

    char szValue[MESSAGE_LENGTH];
    obj = getClientModel(client);
    if(!obj) {
        // PrintToChat(client, "%T", "secure_restriction", client);
        return false;
    }

    if(obj && IsPartValid(obj, part)) {
        obj.GetString(szBinds[part], szValue, sizeof(szValue));
    }

    if(szValue[0] && StrEqual(szValue, item, false)) {
        obj.SetNull(szBinds[part]);
    }

    asJSONO(ccp_GetPackage(client)).Set(pkgKey, obj);
    delete obj;

    return true;
}

JSONObject objModel;

public Processing  cc_proc_OnRebuildString(const int[] props, int part, ArrayList params, int &level, char[] value, int size) {
    if(!SENDER_INDEX(props[1]) || level > levels[part]) {
        return Proc_Continue;
    }

    objModel = getClientModel(0);
    if(!objModel.HasKey("channels")) {
        delete objModel;
        return Proc_Continue;
    }

    JSONArray channels = asJSONA(objModel.Get("channels"));
    delete objModel;

    char szIndent[64];
    params.GetString(0, szIndent, sizeof(szIndent));
    if(FindChannelInChannels_json(channels, szIndent) == -1) {
        delete channels;
        return Proc_Continue;
    }

    delete channels;

    objModel = getClientModel(SENDER_INDEX(props[1]));
    if(!objModel || !IsPartValid(objModel, part)) {
        delete objModel;
        return Proc_Continue;
    }

    static char szValue[MESSAGE_LENGTH];
    if(!objModel.GetString(szBinds[part], szValue, sizeof(szValue)) || !szValue[0]) {
        delete objModel;
        return Proc_Continue;
    }

    if(part == BIND_PREFIX && TranslationPhraseExists(szValue)) {
        Format(szValue, sizeof(szValue), "%T", szValue, props[2]);
    }

    level = levels[part];
    FormatEx(value, size, szValue);

    delete objModel;
    return Proc_Change;
}

stock JSONObject getClientModel(int iClient) {
    JSONObject obj;
    obj = asJSONO(ccp_GetPackage(iClient));

    if(!obj || !obj.HasKey(pkgKey) || !obj.HasKey("auth"))
        return null;
    
    obj = asJSONO(obj.Get(pkgKey));
    return obj;
}

stock bool IsPartValid(JSONObject model, int part) {
    return model.HasKey(szBinds[part]) && !model.IsNull(szBinds[part]);
}