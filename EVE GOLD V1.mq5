//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS - CONFIGURACIÓN GENERAL DEL EA                            |
//+------------------------------------------------------------------+

// === PARÁMETROS HORARIOS ===
input int    HoraInicio = 0;                 // Hora inicio operación servidor (0-23)
input int    HoraFin = 0;                    // Hora cierre operación servidor (0-23)

// === PANEL VISUAL ===
input bool   EnableInfoPanel = true;         // Mostrar panel de información

// === GESTIÓN DE MARTINGALA ===
enum ENUM_LOT_LOGIC
{
    LOGIC_MARTINGALE = 0, // Multiplicar (Ej: 0.01, 0.02, 0.04, 0.08, ...)
    LOGIC_SUMA = 1        // Sumar (Ej: 0.01, 0.02, 0.03, 0.04, ...)
};
input double LoteInicial = 0.01;             // Lote para iniciar serie
input ENUM_LOT_LOGIC ModoAumento = LOGIC_MARTINGALE; // Modo de progresión
input double FactorAumento = 2.0;            // Multiplicador en modo Martingale (usado solo en LOGIC_MARTINGALE)
input int    DistanciaMinimaGrid = 500;      // Distancia mínima en puntos entre órdenes
input bool   EnableMartingaleFollowUp = true; // Abrir operaciones adicionales si la serie entra en pérdida
input int    MaxMartingaleLevels = 15;         // Máximo de niveles en la serie (incluye la inicial)

// === PARÁMETROS OPERATIVOS ===
input double lote = 0.01;                    // Tamaño del lote
input int    tp_points = 2000;               // Take Profit en puntos
input int    sl_points = 3000;               // Stop Loss en puntos (si no usa ATR)
input int    EntryOffsetPoints = 0;          // Offset de entrada desde soporte/resistencia
input int    MinRetracePoints = 3000;         // Retroceso mínimo requerido desde el nivel
input int    SRSkipBars = 1;                 // Velas recientes a ignorar para S/R
input int    PendingOrderMaxAgeHours = 15;   // Tiempo máximo de vida de una orden pendiente
input int    MagicNumber = 281218;           // Magic number para identificación
input string IdentificadorEA = "EVE_GOLD";   // Identificador único del EA
input int    MaxSpreadPoints = 30;           // Spread máximo permitido
input int    MaxSlippagePoints = 100;        // Deslizamiento máximo permitido
input ENUM_TIMEFRAMES SRTimeframe = PERIOD_M5; // Timeframe para detectar soporte/resistencia
input int    SRLookbackBars = 48;           // Velas cerradas a revisar para max/min de S/R
input bool   EnableSR = true;              // Interruptor: activar/desactivar detección S/R

enum EntryExecutionMode
{
    ENTRY_MODE_PENDING_STOP = 1,
    ENTRY_MODE_MARKET_ON_TOUCH = 0
};
input EntryExecutionMode EntryMode = ENTRY_MODE_PENDING_STOP; // STOP pendiente o entrada a mercado al tocar nivel

// === TRAILING STOP VIRTUAL (LÍNEA AMARILLA) ===
input int VirtualStart1 = 150; // Ganancia para 1ra operación (puntos)
input int VirtualStartN = 150; // Ganancia conjunta para 2+ operaciones (puntos)
input int VirtualStep   = 50;  // Puntos a asegurar y cada cuánto se moverá la línea

// === FILTRO EMA200 ===
input bool   EnableEMAFilter = true;        // Filtro EMA
input int    EMAPeriod = 200;                // Período EMA
input ENUM_TIMEFRAMES EMATimeframe = PERIOD_M15; // Timeframe EMA

// === FILTRO RSI ===
input bool   EnableRSIFilter = false;        // Filtro RSI
input int    RSIPeriod = 14;                 // Período RSI
input int    RSI_MaxBuy = 70;                // RSI máximo para compra
input int    RSI_MinSell = 30;               // RSI mínimo para venta
input ENUM_TIMEFRAMES RSITimeframe = PERIOD_M15; // Timeframe RSI

// === FILTRO ADX (Fuerza de Tendencia) ===
input bool   EnableADXFilter = false;        // Filtro ADX (fuerza de tendencia)
input int    ADXPeriod = 14;                 // Período ADX
input double ADXMinValue = 25.0;             // ADX mínimo permitido
input ENUM_TIMEFRAMES ADXTimeframe = PERIOD_H1; // Timeframe ADX

// === FILTRO VOLUMEN ===
input bool   EnableVolumeFilter = true;     // Filtro de volumen
input ENUM_TIMEFRAMES VolumeFilterTimeframe = PERIOD_M15; // Timeframe para filtro volumen
input int    VolumeLookbackBars = 20;        // Velas anteriores para promedio volumen
input double VolumeMinRatio = 1.5;           // Ratio mínimo volumen actual/promedio

// === FILTRO BANDAS DE BOLLINGER ===
input bool   EnableBBFilter = false;         // Activar filtro Bollinger Bands
input int    BBPeriod = 20;                  // Período (20 es estándar para oro)
input double BBDeviation = 2.0;             // Desviación estándar (2.0-2.2 para XAU/USD)
input ENUM_TIMEFRAMES BBTimeframe = PERIOD_M15; // Timeframe para detectar squeeze/ruptura

// === FILTRO DE NOTICIAS ECONÓMICAS ===
input bool   EnableNewsFilter = true;        // Activar filtro de noticias de alto impacto
input int    MinsBeforeNews = 30;            // Bloquear trading minutos antes de la noticia
input int    MinsAfterNews = 30;             // Bloquear trading minutos después de la noticia

// === FILTRO VWAP (Precio Promedio Ponderado por Volumen) ===
input bool   EnableVWAPFilter = false;       // Activar filtro VWAP como soporte/resistencia dinámico
input ENUM_TIMEFRAMES VWAPTimeframe = PERIOD_H1; // Timeframe para calcular VWAP
input int    VWAPLookbackBars = 20;          // Velas para acumular VWAP

//+------------------------------------------------------------------+
//| CONSTANTES GLOBALES                                              |
//+------------------------------------------------------------------+
const string PANEL_BG_NAME = "PANEL_BG";
const string PANEL_LINE_PREFIX = "PANEL_LINE_";
const string LEVEL_LINE_PREFIX = "LEVEL_LINE_";

//+------------------------------------------------------------------+
//| OBJETOS GLOBALES                                                 |
//+------------------------------------------------------------------+
CTrade trade;

// Variables para el trailing virtual
double VirtualLineBuy = 0.0;
double VirtualLineSell = 0.0;

// Handles globales para indicadores (persistentes, evita crear/destruir en cada tick)
int handleEMA = INVALID_HANDLE;    // EMA para filtro de dirección
int handleRSI = INVALID_HANDLE;    // RSI para filtro de condición extrema
int handleADX = INVALID_HANDLE;    // ADX para filtro de fuerza de tendencia
int handleBB = INVALID_HANDLE;     // Bollinger Bands para detección de squeeze/ruptura

string GetEntryExecutionModeLabel()
{
    if(EntryMode == ENTRY_MODE_MARKET_ON_TOUCH)
        return "MERCADO_AL_TOQUE";
    return "ORDEN_PENDIENTE_STOP";
}

ENUM_TIMEFRAMES GetSupportResistanceTimeframe()
{
    return SRTimeframe;
}

string TimeframeLabel(ENUM_TIMEFRAMES tf)
{
    if(tf == PERIOD_M1)  return "M1";
    if(tf == PERIOD_M5)  return "M5";
    if(tf == PERIOD_M15) return "M15";
    if(tf == PERIOD_M30) return "M30";
    if(tf == PERIOD_H1)  return "H1";
    if(tf == PERIOD_H3)  return "H3";
    if(tf == PERIOD_H4)  return "H4";
    if(tf == PERIOD_D1)  return "D1";
    if(tf == PERIOD_W1)  return "W1";
    if(tf == PERIOD_MN1) return "MN1";
    return EnumToString(tf);
}

bool GetSupportResistanceLevels(ENUM_TIMEFRAMES tf, int lookbackBars, double &support, double &resistance)
{
    support = 0.0;
    resistance = 0.0;

    int bars = MathMax(1, lookbackBars);
    int startShift = MathMax(1, SRSkipBars);
    double lows[];
    double highs[];

    int copiedLow = CopyLow(_Symbol, tf, startShift, bars, lows);
    int copiedHigh = CopyHigh(_Symbol, tf, startShift, bars, highs);

    if(copiedLow <= 0 || copiedHigh <= 0)
    {
        Print("[ERROR] No se pudo copiar datos de S/R en ", TimeframeLabel(tf),
              " | lookback=", bars);
        return false;
    }

    support = lows[0];
    for(int i = 1; i < copiedLow; i++)
        if(lows[i] < support)
            support = lows[i];

    resistance = highs[0];
    for(int j = 1; j < copiedHigh; j++)
        if(highs[j] > resistance)
            resistance = highs[j];

    return (support > 0.0 && resistance > 0.0 && resistance > support);
}

//+------------------------------------------------------------------+
//| Dibuja una linea corta horizontal fija (sin mover lineas previas) |
//+------------------------------------------------------------------+
string BuildLevelLineName(string levelType, datetime markerTime)
{
    return LEVEL_LINE_PREFIX + levelType + "_" + IntegerToString((int)markerTime);
}

void DrawSRShortLevelLineFixed(ENUM_TIMEFRAMES lineTf, string levelType, datetime markerTime, double price, color lineColor)
{
    if(price <= 0.0 || markerTime <= 0)
        return;

    string name = BuildLevelLineName(levelType, markerTime);
    if(ObjectFind(0, name) >= 0)
        return; // Ya fue dibujada para este nivel/vela de analisis

    datetime t1 = iTime(_Symbol, lineTf, 0);
    if(t1 <= 0)
        t1 = TimeCurrent();

    datetime t2 = t1 + PeriodSeconds(lineTf);

    ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);

    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
    ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawSupportResistanceOnChart(ENUM_TIMEFRAMES lineTf, datetime markerTime, double support, double resistance)
{
    DrawSRShortLevelLineFixed(lineTf, "SUPPORT", markerTime, support, clrRed);
    DrawSRShortLevelLineFixed(lineTf, "RESIST", markerTime, resistance, clrLimeGreen);
}

//+------------------------------------------------------------------+
//| Funciones del panel visual                                       |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    if(!EnableInfoPanel) { return; }

    long chartID = ChartID();

    if(ObjectFind(0, PANEL_BG_NAME) < 0)
    {
        ObjectCreate(0, PANEL_BG_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_XSIZE, 370);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_YSIZE, 285);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_BGCOLOR, clrBlack);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_COLOR, clrDodgerBlue);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_BACK, false);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, PANEL_BG_NAME, OBJPROP_SELECTABLE, false);
    }
}

void UpdateInfoPanel(string panelText)
{
    if(!EnableInfoPanel)
    {
        DeleteInfoPanel();
        return;
    }

    if(ObjectFind(0, PANEL_BG_NAME) < 0)
        CreateInfoPanel();

    string lines[];
    StringReplace(panelText, "\r", "");
    int lineCount = StringSplit(panelText, '\n', lines);

    // Actualizar líneas existentes o crear nuevas sin eliminar
    int startY = 30;
    int lineStep = 16;
    for(int i = 0; i < lineCount; i++)
    {
        string line = lines[i];
        if(line == "") { continue; }

        string objName = PANEL_LINE_PREFIX + IntegerToString(i);
        
        // Crear solo si no existe; de lo contrario, actualizar texto
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 20);
            ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, startY + (i * lineStep));
            ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
            ObjectSetInteger(0, objName, OBJPROP_BACK, false);
            ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
        }
        
        // Actualizar color según contenido
        color lineColor = clrWhite;
        if(StringFind(line, "TP acumulado:") == 0)
        {
            if(StringFind(line, "-") >= 0)
                lineColor = clrTomato;
            else if(StringFind(line, "+") >= 0)
                lineColor = clrLimeGreen;
        }
        ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
        
        // Actualizar texto (más eficiente que delete/create)
        ObjectSetString(0, objName, OBJPROP_TEXT, line);
    }

    ChartRedraw(0);
}

void DeleteInfoPanel()
{
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, PANEL_LINE_PREFIX) == 0)
            ObjectDelete(0, name);
    }
    if(ObjectFind(0, PANEL_BG_NAME) >= 0)
        ObjectDelete(0, PANEL_BG_NAME);
}

//+------------------------------------------------------------------+
//| Limpia todas las líneas de soporte/resistencia dibujadas        |
//+------------------------------------------------------------------+
void DeleteAllLevelLines()
{
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, LEVEL_LINE_PREFIX) == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Limpia todas las líneas de noticias dibujadas                    |
//+------------------------------------------------------------------+
void DeleteAllNewsLines()
{
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "NEWS_LINE_") == 0 || StringFind(name, "NEWS_LABEL_") == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| Función: Construir comentario de orden con identificador         |
//+------------------------------------------------------------------+
string BuildOrderComment(string tag)
{
    if(StringLen(IdentificadorEA) <= 0)
        return tag;
    return IdentificadorEA + "|" + tag;
}

//+------------------------------------------------------------------+
//| Suma el resultado neto acumulado de operaciones del EA           |
//| HistorySelect se ejecuta una sola vez al cambiar la historia    |
//+------------------------------------------------------------------+
static datetime lastHistoryTime = 0;
void MaybeUpdateHistory()
{
    static datetime lastHistoryRefresh = 0;
    datetime now = TimeCurrent();
    
    // Actualizar cada 60 segundos o cuando cambien las barras
    if(now - lastHistoryRefresh > 60)
    {
        HistorySelect(0, TimeCurrent());
        lastHistoryRefresh = now;
    }
}

double GetAccumulatedEAProfitUSD()
{
    MaybeUpdateHistory();

    double total = 0.0;
    string idPrefix = IdentificadorEA + "|";
    int deals = HistoryDealsTotal();

    for(int i = 0; i < deals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

        long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        string dealComment = HistoryDealGetString(ticket, DEAL_COMMENT);
        bool belongsByMagic = (dealMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(dealComment, idPrefix) == 0);

        if(!belongsByMagic && !belongsById) continue;

        total += HistoryDealGetDouble(ticket, DEAL_PROFIT)
              +  HistoryDealGetDouble(ticket, DEAL_SWAP)
              +  HistoryDealGetDouble(ticket, DEAL_COMMISSION);
    }

    return total;
}

//+------------------------------------------------------------------+
//| Verifica si ya se creó una orden del EA en esta vela H4         |
//+------------------------------------------------------------------+
bool HasOrderPlacementInCurrentH4(datetime h4OpenTime)
{
    if(h4OpenTime <= 0)
        return false;

    string idPrefix = IdentificadorEA + "|";

    // 1) Revisar órdenes pendientes activas creadas en la H4 actual
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) { continue; }
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) { continue; }

        datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
        if(setupTime < h4OpenTime)
            continue;

        long orderMagic = OrderGetInteger(ORDER_MAGIC);
        string orderComment = OrderGetString(ORDER_COMMENT);
        bool belongsByMagic = (orderMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(orderComment, idPrefix) == 0);

        if(belongsByMagic || belongsById)
            return true;
    }

    // 2) Revisar historial de órdenes creadas en la H4 actual
    MaybeUpdateHistory();
    if(!HistorySelect(h4OpenTime, TimeCurrent()))
        return false;

    int totalHistoryOrders = HistoryOrdersTotal();
    for(int i = totalHistoryOrders - 1; i >= 0; i--)
    {
        ulong ticket = HistoryOrderGetTicket(i);
        if(ticket == 0) continue;
        if(HistoryOrderGetString(ticket, ORDER_SYMBOL) != _Symbol) continue;

        datetime setupTime = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
        if(setupTime < h4OpenTime)
            continue;

        long orderMagic = HistoryOrderGetInteger(ticket, ORDER_MAGIC);
        string orderComment = HistoryOrderGetString(ticket, ORDER_COMMENT);
        bool belongsByMagic = (orderMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(orderComment, idPrefix) == 0);

        if(belongsByMagic || belongsById)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Verifica si ya hubo entrada a mercado del EA en esta vela       |
//+------------------------------------------------------------------+
bool HasMarketEntryInCurrentCycle(datetime cycleOpenTime)
{
    if(cycleOpenTime <= 0)
        return false;

    string idPrefix = IdentificadorEA + "|";

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != _Symbol) { continue; }

        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        if(openTime < cycleOpenTime) { continue; }

        long posMagic = PositionGetInteger(POSITION_MAGIC);
        string posComment = PositionGetString(POSITION_COMMENT);
        bool belongsByMagic = (posMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(posComment, idPrefix) == 0);

        if(belongsByMagic || belongsById)
            return true;
    }

    MaybeUpdateHistory();
    if(!HistorySelect(cycleOpenTime, TimeCurrent()))
        return false;

    int deals = HistoryDealsTotal();
    for(int i = deals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

        datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        if(dealTime < cycleOpenTime) continue;

        long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
        string dealComment = HistoryDealGetString(ticket, DEAL_COMMENT);
        bool belongsByMagic = (dealMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(dealComment, idPrefix) == 0);

        if(belongsByMagic || belongsById)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    long chartID = ChartID();

    // Entorno visual del grafico
    ChartSetInteger(chartID, CHART_COLOR_BACKGROUND, clrBlack);
    ChartSetInteger(chartID, CHART_COLOR_FOREGROUND, clrWhite);
    ChartSetInteger(chartID, CHART_SHOW_GRID, false);
    ChartSetInteger(chartID, CHART_MODE, CHART_CANDLES);
    ChartSetInteger(chartID, CHART_COLOR_CHART_UP, clrDeepSkyBlue);
    ChartSetInteger(chartID, CHART_COLOR_CHART_DOWN, clrDarkBlue);
    ChartSetInteger(chartID, CHART_COLOR_CANDLE_BULL, clrDeepSkyBlue);
    ChartSetInteger(chartID, CHART_COLOR_CANDLE_BEAR, clrDarkBlue);

    if(EnableInfoPanel)
        CreateInfoPanel();

    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(MathMax(0, MaxSlippagePoints));

    // Inicializar handles de indicadores (una sola vez)
    if(EnableEMAFilter)
    {
        handleEMA = iMA(_Symbol, EMATimeframe, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(handleEMA == INVALID_HANDLE)
            Print("[WARNING] No se pudo crear handle EMA. Filtro EMA desactivado.");
    }

    if(EnableRSIFilter)
    {
        handleRSI = iRSI(_Symbol, RSITimeframe, RSIPeriod, PRICE_CLOSE);
        if(handleRSI == INVALID_HANDLE)
            Print("[WARNING] No se pudo crear handle RSI. Filtro RSI desactivado.");
    }

    if(EnableADXFilter)
    {
        handleADX = iADX(_Symbol, ADXTimeframe, ADXPeriod);
        if(handleADX == INVALID_HANDLE)
            Print("[WARNING] No se pudo crear handle ADX. Filtro ADX desactivado.");
    }

    if(EnableBBFilter)
    {
        handleBB = iBands(_Symbol, BBTimeframe, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
        if(handleBB == INVALID_HANDLE)
            Print("[WARNING] No se pudo crear handle Bollinger Bands. Filtro BB desactivado.");
    }

    int recoveredPositions = CountOpenPositions();
    int recoveredOrders = CountPendingOrders();

    Print("[EA] Iniciado | ID=", IdentificadorEA,
          " | Magic=", MagicNumber, " | Posiciones recuperadas=", recoveredPositions,
          " | Ordenes pendientes recuperadas=", recoveredOrders);
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    DeleteInfoPanel();
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    { // Limpiar líneas de noticias y de niveles
        DeleteAllNewsLines();
        DeleteAllLevelLines();
    }

    // Liberar handles de indicadores
    if(handleEMA != INVALID_HANDLE)
        IndicatorRelease(handleEMA);
    if(handleRSI != INVALID_HANDLE)
        IndicatorRelease(handleRSI);
    if(handleADX != INVALID_HANDLE)
        IndicatorRelease(handleADX);
    if(handleBB != INVALID_HANDLE)
        IndicatorRelease(handleBB);

    Comment("");
}

//+------------------------------------------------------------------+
//| Función: Verificar si ya existe SellStop en el soporte           |
//| Busca en órdenes pendientes si hay un SELL_STOP cercano al precio|
//+------------------------------------------------------------------+
bool ExistsSellStopAtPrice(double price)
{
    if(price <= 0.0)
        return false;

    // Tolerancia: ±2 ticks para considerar "cercano"
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tolerance = tickSize * 2;
    double priceMin = price - tolerance;
    double priceMax = price + tolerance;

    string idPrefix = IdentificadorEA + "|";

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;

        // Validar que sea del mismo símbolo y del EA
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

        long orderMagic = OrderGetInteger(ORDER_MAGIC);
        string orderComment = OrderGetString(ORDER_COMMENT);
        bool belongsByMagic = (orderMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(orderComment, idPrefix) == 0);

        if(!belongsByMagic && !belongsById) continue;

        // Buscar si es SELL_STOP en el rango de precio
        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(orderType == ORDER_TYPE_SELL_STOP)
        {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(orderPrice >= priceMin && orderPrice <= priceMax)
                return true; // Existe SellStop cercano
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Función: Verificar si ya existe BuyStop en la resistencia        |
//| Busca en órdenes pendientes si hay un BUY_STOP cercano al precio |
//+------------------------------------------------------------------+
bool ExistsBuyStopAtPrice(double price)
{
    if(price <= 0.0)
        return false;

    // Tolerancia: ±2 ticks para considerar "cercano"
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tolerance = tickSize * 2;
    double priceMin = price - tolerance;
    double priceMax = price + tolerance;

    string idPrefix = IdentificadorEA + "|";

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;

        // Validar que sea del mismo símbolo y del EA
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

        long orderMagic = OrderGetInteger(ORDER_MAGIC);
        string orderComment = OrderGetString(ORDER_COMMENT);
        bool belongsByMagic = (orderMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(orderComment, idPrefix) == 0);

        if(!belongsByMagic && !belongsById) continue;

        // Buscar si es BUY_STOP en el rango de precio
        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(orderType == ORDER_TYPE_BUY_STOP)
        {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(orderPrice >= priceMin && orderPrice <= priceMax)
                return true; // Existe BuyStop cercano
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Función: Convertir puntos a distancia en precio                  |
//+------------------------------------------------------------------+
double PointsToPriceDistance(int points)
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    return (double)points * point;
}

//+------------------------------------------------------------------+
//| Función: Obtener spread actual en puntos y en precio            |
//+------------------------------------------------------------------+
double GetCurrentSpreadPrice()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    return MathMax(0.0, ask - bid);
}

double GetCurrentSpreadPoints()
{
    double spreadPrice = GetCurrentSpreadPrice();
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(point <= 0.0) return 0.0;
    return spreadPrice / point;
}

//+------------------------------------------------------------------+
//| Función: Contar posiciones abiertas                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    string idPrefix = IdentificadorEA + "|";
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != _Symbol)
            continue;

        long posMagic = PositionGetInteger(POSITION_MAGIC);
        string posComment = PositionGetString(POSITION_COMMENT);
        bool belongsByMagic = (posMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(posComment, idPrefix) == 0);

        if(belongsByMagic || belongsById)
            count++;
    }
    return count;
}

int CountOpenPositionsByType(ENUM_POSITION_TYPE posType)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i))
            continue;
        
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType)
            count++;
    }
    return count;
}

double NormalizeLotBySymbol(double rawLot)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(stepLot <= 0.0)
        stepLot = 0.01;

    double lot = MathMax(minLot, rawLot);
    lot = MathMin(maxLot, lot);
    lot = MathFloor((lot / stepLot) + 0.5) * stepLot;

    if(lot < minLot)
        lot = minLot;
    if(lot > maxLot)
        lot = maxLot;

    return lot;
}

bool GetMartingaleSideStats(ENUM_POSITION_TYPE posType,
                            int &count,
                            double &profit,
                            double &lastOpenPrice,
                            double &lastVolume,
                            double &lastPositionProfit)
{
    count = 0;
    profit = 0.0;
    lastOpenPrice = 0.0;
    lastVolume = 0.0;
    lastPositionProfit = 0.0;
    datetime lastOpenTime = 0;
    string idPrefix = IdentificadorEA + "|";

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != _Symbol)
            continue;

        long posMagic = PositionGetInteger(POSITION_MAGIC);
        string posComment = PositionGetString(POSITION_COMMENT);
        bool belongsByMagic = (posMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(posComment, idPrefix) == 0);
        if(!belongsByMagic && !belongsById)
            continue;

        ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if(currentType != posType)
            continue;

        count++;
        profit += PositionGetDouble(POSITION_PROFIT);

        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        if(openTime >= lastOpenTime)
        {
            lastOpenTime = openTime;
            lastOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            lastVolume = PositionGetDouble(POSITION_VOLUME);
            lastPositionProfit = PositionGetDouble(POSITION_PROFIT);
        }
    }

    return (count > 0);
}

double GetNextMartingaleLotFromLast(double lastVolume)
{
    double base = (lastVolume > 0.0 ? lastVolume : LoteInicial);
    double nextLot = base;

    if(ModoAumento == LOGIC_MARTINGALE)
    {
        // Multiplicar por FactorAumento: 0.01, 0.02, 0.04, 0.08, ...
        nextLot = base * MathMax(1.0, FactorAumento);
    }
    else
    {
        // Sumar LoteInicial: 0.01, 0.02, 0.03, 0.04, ...
        nextLot = base + LoteInicial;
    }

    return NormalizeLotBySymbol(nextLot);
}

double GetProfitPerPointPerLot()
{
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
        return 0.0;

    return tickValue * (point / tickSize);
}

bool PositionBelongsToEAByIndex(int index)
{
    if(PositionGetSymbol(index) != _Symbol)
        return false;

    string idPrefix = IdentificadorEA + "|";
    long posMagic = PositionGetInteger(POSITION_MAGIC);
    string posComment = PositionGetString(POSITION_COMMENT);
    bool belongsByMagic = (posMagic == MagicNumber);
    bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(posComment, idPrefix) == 0);

    if(belongsByMagic || belongsById)
        return true;

    return false;
}

bool GetBasketSideAggregation(ENUM_POSITION_TYPE sideType,
                              int &sideCount,
                              double &totalVolume,
                              double &weightedPriceSum)
{
    sideCount = 0;
    totalVolume = 0.0;
    weightedPriceSum = 0.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i))
            continue;

        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != sideType)
            continue;

        double vol = PositionGetDouble(POSITION_VOLUME);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        totalVolume += vol;
        weightedPriceSum += (open * vol);
        sideCount++;
    }

    return (sideCount > 0 && totalVolume > 0.0);
}

double FitLotToMargin(bool isBuy, double requestedLot, double price, double &requiredMargin)
{
    requiredMargin = 0.0;

    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(stepLot <= 0.0)
        stepLot = 0.01;

    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginBudget = freeMargin * 0.7;  // Usar 70% del margen libre
    if(marginBudget <= 0.0)
        return 0.0;

    ENUM_ORDER_TYPE orderType = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
    double lot = NormalizeLotBySymbol(requestedLot);

    while(lot >= minLot)
    {
        double marginNeed = 0.0;
        if(OrderCalcMargin(orderType, _Symbol, lot, price, marginNeed) && marginNeed > 0.0)
        {
            if(marginNeed <= marginBudget)
            {
                requiredMargin = marginNeed;
                return lot;
            }
        }

        lot = NormalizeLotBySymbol(lot - stepLot);
        if(lot < minLot)
            break;
    }

    return 0.0;
}

//+------------------------------------------------------------------+
//| Función: Contar órdenes pendientes                               |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
           OrderGetInteger(ORDER_MAGIC) == MagicNumber)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Función: Contar órdenes pendientes por tipo                      |
//+------------------------------------------------------------------+
int CountPendingOrdersByType(ENUM_ORDER_TYPE type)
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0) continue;

        if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
           (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Función: Eliminar órdenes pendientes expiradas                  |
//+------------------------------------------------------------------+
void DeleteExpiredPendingOrders()
{
    if(PendingOrderMaxAgeHours <= 0)
        return;

    datetime now = TimeCurrent();
    int maxAgeSeconds = PendingOrderMaxAgeHours * 3600;
    string idPrefix = IdentificadorEA + "|";

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket == 0)
            continue;

        if(OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;

        long orderMagic = OrderGetInteger(ORDER_MAGIC);
        string orderComment = OrderGetString(ORDER_COMMENT);
        bool belongsByMagic = (orderMagic == MagicNumber);
        bool belongsById = (StringLen(IdentificadorEA) > 0 && StringFind(orderComment, idPrefix) == 0);
        if(!belongsByMagic && !belongsById)
            continue;

        ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        bool isPendingStop = (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP);
        if(!isPendingStop)
            continue;

        datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
        if(setupTime <= 0)
            continue;

        if((now - setupTime) >= maxAgeSeconds)
        {
            if(trade.OrderDelete(ticket))
            {
                Print("[EXPIRE] Orden pendiente borrada por edad: ticket=", ticket,
                      " | ageHours=", DoubleToString((now - setupTime) / 3600.0, 1),
                      " | type=", EnumToString(orderType));
            }
            else
            {
                Print("[EXPIRE][ERROR] No se pudo borrar orden pendiente ticket=", ticket,
                      " | error=", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Función: Obtener hora actual formateada (HH:MM:SS GMT)           |
//+------------------------------------------------------------------+
string GetFormattedCurrentTime()
{
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);
    
    string hour = (dt.hour < 10 ? "0" : "") + IntegerToString(dt.hour);
    string min = (dt.min < 10 ? "0" : "") + IntegerToString(dt.min);
    string sec = (dt.sec < 10 ? "0" : "") + IntegerToString(dt.sec);
    
    return hour + ":" + min + ":" + sec + " GMT";
}

//+------------------------------------------------------------------+
//| Función: Identificar mercados abiertos (según hora GMT)          |
//+------------------------------------------------------------------+
string GetActiveMarketsInfo()
{
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);
    int hour = dt.hour;
    
    // Horarios de apertura (en GMT, lunes-viernes)
    bool tokyoOpen = (hour >= 0 && hour < 9);           // 00:00 - 08:59
    bool londonOpen = (hour >= 8 && hour < 17);         // 08:00 - 16:59 (GMT)
    bool newyorkOpen = (hour >= 13 && hour < 22);       // 13:00 - 21:59 (GMT)
    bool sydneyOpen = (hour >= 22 || hour < 7);         // 22:00 - 06:59 (cruza día)
    
    // Dar un poco de overlap para horarios de verano
    string active = "";
    if(tokyoOpen) { active += (active != "" ? " | " : "") + "[Tokio]"; }
    if(sydneyOpen) { active += (active != "" ? " | " : "") + "[Sydney]"; }
    if(londonOpen) { active += (active != "" ? " | " : "") + "[Londres]"; }
    if(newyorkOpen) { active += (active != "" ? " | " : "") + "[NY]"; }
    
    if(active == "")
        active = "Mercados cerrados";
    
    return active;
}

//+------------------------------------------------------------------+
//| Función: Filtro horario                                          |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime dt;
    TimeCurrent(dt);
    int hour = dt.hour;
    
    if(HoraInicio < HoraFin)
        return (hour >= HoraInicio && hour < HoraFin);
    else if(HoraInicio > HoraFin)
        return (hour >= HoraInicio || hour < HoraFin);
    else  // 24h
        return true;
}

//+------------------------------------------------------------------+
//| Función para normalizar precios al paso exacto del bróker        |
//+------------------------------------------------------------------+
double NormalizeToTickSize(double price)
{
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize <= 0) return NormalizeDouble(price, _Digits);
    return MathRound(price / tickSize) * tickSize;
}

//+------------------------------------------------------------------+
//| Función: Mejora de distancia mínima incluyendo Freeze Level      |
//+------------------------------------------------------------------+
double GetPendingMinDistancePrice()
{
    int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    int maxLevel = MathMax(stopsLevel, freezeLevel); // Usar el mayor de los dos
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Añadimos un margen de seguridad de 2 ticks
    return MathMax(maxLevel * point, tickSize * 2);
}

//+------------------------------------------------------------------+
//| Función: Validar precio SellStop antes de enviar                 |
//+------------------------------------------------------------------+
bool IsValidSellStopPrice(double price, double bid)
{
    double minDist = GetPendingMinDistancePrice();
    return (price <= (bid - minDist));
}

//+------------------------------------------------------------------+
//| Función: Validar precio BuyStop antes de enviar                  |
//+------------------------------------------------------------------+
bool IsValidBuyStopPrice(double price, double ask)
{
    double minDist = GetPendingMinDistancePrice();
    return (price >= (ask + minDist));
}

//+------------------------------------------------------------------+
//| Filtro EMA: Buy solo arriba, Sell solo abajo                    |
//+------------------------------------------------------------------+
bool PassesEMAFilter(bool isBuy, double &emaValue)
{
    emaValue = 0.0;
    if(!EnableEMAFilter)
        return true;

    if(handleEMA == INVALID_HANDLE)
        return false;

    double emaBuf[];
    int copied = CopyBuffer(handleEMA, 0, 0, 1, emaBuf);

    if(copied <= 0)
        return false;

    emaValue = emaBuf[0];
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double mid = (ask + bid) * 0.5;

    if(isBuy)
        return (mid > emaValue);
    return (mid < emaValue);
}

//+------------------------------------------------------------------+
//| Filtro RSI: Buy (50-70) y Sell (30-50) en vela cerrada          |
//+------------------------------------------------------------------+
bool PassesRSIFilter(bool isBuy, double &rsiValue)
{
    rsiValue = 0.0;
    if(!EnableRSIFilter)
        return true;

    if(handleRSI == INVALID_HANDLE)
        return false;

    double rsiBuf[];
    int copied = CopyBuffer(handleRSI, 0, 1, 1, rsiBuf);

    if(copied <= 0)
        return false;

    rsiValue = rsiBuf[0];

    int rsiMaxBuySafe = MathMax(51, RSI_MaxBuy);
    int rsiMinSellSafe = MathMin(49, RSI_MinSell);

    if(isBuy)
        return (rsiValue > 50.0 && rsiValue < (double)rsiMaxBuySafe);
    return (rsiValue < 50.0 && rsiValue > (double)rsiMinSellSafe);
}

//+------------------------------------------------------------------+
//| Obtiene OHLC de vela cerrada en timeframe especificado           |
//+------------------------------------------------------------------+
bool GetCandleDataByTimeframe(ENUM_TIMEFRAMES tf, double &openPrice, double &highPrice, double &lowPrice, double &closePrice, datetime &closeTime)
{
    openPrice = 0.0;
    highPrice = 0.0;
    lowPrice = 0.0;
    closePrice = 0.0;
    closeTime = 0;

    double openBuf[];
    double highBuf[];
    double lowBuf[];
    double closeBuf[];
    datetime timeBuf[];

    int copiedOpen = CopyOpen(_Symbol, tf, 1, 1, openBuf);
    int copiedHigh = CopyHigh(_Symbol, tf, 1, 1, highBuf);
    int copiedLow = CopyLow(_Symbol, tf, 1, 1, lowBuf);
    int copiedClose = CopyClose(_Symbol, tf, 1, 1, closeBuf);
    int copiedTime = CopyTime(_Symbol, tf, 1, 1, timeBuf);

    if(copiedOpen <= 0 || copiedHigh <= 0 || copiedLow <= 0 || copiedClose <= 0 || copiedTime <= 0)
        return false;

    openPrice = openBuf[0];
    highPrice = highBuf[0];
    lowPrice = lowBuf[0];
    closePrice = closeBuf[0];
    closeTime = timeBuf[0];
    return true;
}

//+------------------------------------------------------------------+
//| Obtiene ADX en vela cerrada del timeframe configurado           |
//+------------------------------------------------------------------+
bool GetADXValue(double &adxValue)
{
    adxValue = 0.0;

    if(handleADX == INVALID_HANDLE)
        return false;

    double adxBuf[];
    int copied = CopyBuffer(handleADX, 0, 1, 1, adxBuf); // vela cerrada

    if(copied <= 0)
        return false;

    adxValue = adxBuf[0];
    return (adxValue > 0.0);
}

//+------------------------------------------------------------------+
//| Obtiene un ATR cerrado para el periodo y timeframe indicados     |
//+------------------------------------------------------------------+
//| Filtro ADX: solo operar con fuerza de tendencia suficiente      |
//+------------------------------------------------------------------+
bool PassesADXFilter(double &adxValue)
{
    adxValue = 0.0;
    if(!EnableADXFilter)
        return true;

    if(!GetADXValue(adxValue))
        return false;

    double adxMinSafe = MathMax(1.0, ADXMinValue);
    return (adxValue >= adxMinSafe);
}

//+------------------------------------------------------------------+
//| Filtro Bollinger Bands: detecta squeeze o ruptura               |
//+------------------------------------------------------------------+
bool PassesBBFilter(bool isBuy, double &bbUpper, double &bbMiddle, double &bbLower, double &bbWidth)
{
    bbUpper = 0.0;
    bbMiddle = 0.0;
    bbLower = 0.0;
    bbWidth = 0.0;

    if(!EnableBBFilter)
        return true;

    if(handleBB == INVALID_HANDLE)
        return false;

    // iBands devuelve 3 buffers: 0=Upper, 1=Middle, 2=Lower
    double upperBuf[], middleBuf[], lowerBuf[];
    int copiedUpper = CopyBuffer(handleBB, 0, 0, 1, upperBuf);
    int copiedMiddle = CopyBuffer(handleBB, 1, 0, 1, middleBuf);
    int copiedLower = CopyBuffer(handleBB, 2, 0, 1, lowerBuf);

    if(copiedUpper <= 0 || copiedMiddle <= 0 || copiedLower <= 0)
        return false;

    bbUpper = upperBuf[0];
    bbMiddle = middleBuf[0];
    bbLower = lowerBuf[0];
    bbWidth = bbUpper - bbLower;

    if(bbWidth <= 0.0)
        return false;

    // Obtener precio actual
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double mid = (ask + bid) * 0.5;

    // Detectar Squeeze: bandas muy apretadas (volatilidad baja)
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double bbWidthInPoints = (point > 0.0 ? bbWidth / point : 0.0);
    double squeezeThresholdPoints = 50.0;

    if(bbWidthInPoints < squeezeThresholdPoints)
        return true;

    // Detectar Ruptura: precio toca/cruza las bandas
    if(isBuy && mid >= bbUpper)
        return true;
    if(!isBuy && mid <= bbLower)
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| Obtiene volumen actual y promedio de velas anteriores            |
//+------------------------------------------------------------------+
bool GetStandardVolumeMetrics(double &currentVolume, double &averageVolume)
{
    currentVolume = 0.0;
    averageVolume = 0.0;

    int lookback = MathMax(2, VolumeLookbackBars);
    long volumeBuf[];
    ArraySetAsSeries(volumeBuf, true);

    int copied = CopyTickVolume(_Symbol, VolumeFilterTimeframe, 1, lookback, volumeBuf);
    if(copied < lookback)
        return false;

    currentVolume = (double)volumeBuf[0];

    double sum = 0.0;
    for(int i = 1; i < copied; i++)
        sum += (double)volumeBuf[i];

    if(copied <= 1)
        return false;

    averageVolume = sum / (double)(copied - 1);
    return (averageVolume > 0.0);
}

//+------------------------------------------------------------------+
//| Calcula VWAP: Precio Promedio Ponderado por Volumen              |
//+------------------------------------------------------------------+
double GetVWAP(ENUM_TIMEFRAMES tf, int lookbackBars)
{
    if(!EnableVWAPFilter)
        return 0.0;

    int bars = MathMax(1, lookbackBars);
    double highs[], lows[], closes[];
    long volumes[];
    
    if(CopyHigh(_Symbol, tf, 0, bars, highs) <= 0 ||
       CopyLow(_Symbol, tf, 0, bars, lows) <= 0 ||
       CopyClose(_Symbol, tf, 0, bars, closes) <= 0 ||
       CopyTickVolume(_Symbol, tf, 0, bars, volumes) <= 0)
        return 0.0;

    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(volumes, true);

    double typicalPrice = 0.0;
    double numerator = 0.0;
    double denominator = 0.0;

    for(int i = bars - 1; i >= 0; i--)
    {
        typicalPrice = (highs[i] + lows[i] + closes[i]) / 3.0;
        numerator += typicalPrice * (double)volumes[i];
        denominator += (double)volumes[i];
    }

    if(denominator <= 0.0)
        return 0.0;

    return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Filtro VWAP: valida si precio está en relación correcta con VWAP|
//+------------------------------------------------------------------+
bool PassesVWAPFilter(bool isBuy, double &vwapValue)
{
    vwapValue = 0.0;
    
    if(!EnableVWAPFilter)
        return true;

    vwapValue = GetVWAP(VWAPTimeframe, VWAPLookbackBars);
    
    if(vwapValue <= 0.0)
        return true;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Para BUY: precio debe estar por encima del VWAP (VWAP actúa como soporte dinámico)
    if(isBuy)
        return (ask > vwapValue);

    // Para SELL: precio debe estar por debajo del VWAP (VWAP actúa como resistencia dinámica)
    return (bid < vwapValue);
}

//+------------------------------------------------------------------+
//| Filtro de volumen para ruptura por lado (buy/sell)              |
//+------------------------------------------------------------------+
bool PassesVolumeFilter(bool isBuy, double &currentVolume, double &averageVolume)
{
    currentVolume = 0.0;
    averageVolume = 0.0;

    if(!EnableVolumeFilter)
        return true;

    if(!GetStandardVolumeMetrics(currentVolume, averageVolume))
        return false;

    double ratioSafe = MathMax(1.0, VolumeMinRatio);
    if(currentVolume < (averageVolume * ratioSafe))
        return false;

    double openPrice = 0.0;
    double highPrice = 0.0;
    double lowPrice = 0.0;
    double closePrice = 0.0;
    datetime closeTime = 0;

    if(!GetCandleDataByTimeframe(VolumeFilterTimeframe, openPrice, highPrice, lowPrice, closePrice, closeTime))
        return false;

    if(isBuy)
        return (closePrice > openPrice);
    return (closePrice < openPrice);
}

//+------------------------------------------------------------------+
//| Función: Inicio de día servidor (00:00)                         |
//+------------------------------------------------------------------+
datetime GetCurrentDayStart()
{
    datetime dayStart = iTime(_Symbol, GetSupportResistanceTimeframe(), 0);
    if(dayStart > 0)
        return dayStart;

    MqlDateTime dt;
    TimeCurrent(dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Detecta si estamos en ventana de noticia de alto impacto (USA)   |
//| Lee el calendario económico automático de MQL5                   |
//+------------------------------------------------------------------+
bool IsNewsTimeActive()
{
    if(!EnableNewsFilter)
        return false;

    datetime currentTime = TimeCurrent();
    datetime startDate = currentTime - (24 * 3600);   // Ayer (búsqueda atrás)
    datetime endDate = currentTime + (48 * 3600);     // 48 horas adelante
    
    int beforeWindow = MinsBeforeNews * 60;   // Convertir minutos a segundos
    int afterWindow = MinsAfterNews * 60;
    
    MqlCalendarEvent events[];
    // Obtener todos los eventos económicos disponibles
    int eventCount = CalendarEventByCountry("US", events);
    
    if(eventCount > 0)
    {
        for(int i = 0; i < eventCount; i++)
        {
            // Filtrar solo eventos de impacto HIGH
            if(events[i].importance != CALENDAR_IMPORTANCE_HIGH)
                continue;
            
            // Obtener historial de valores para este evento
            MqlCalendarValue values[];
            int valueCount = CalendarValueHistory(values, startDate, endDate, "US");
            
            if(valueCount > 0)
            {
                for(int j = 0; j < valueCount; j++)
                {
                    // Verificar si este valor pertenece al evento actual
                    if(values[j].event_id != events[i].id)
                        continue;
                    
                    datetime eventTime = values[j].time;
                    datetime blockStart = eventTime - beforeWindow;
                    datetime blockEnd = eventTime + afterWindow;
                    
                    // Verificar si tiempo actual está dentro de la ventana de bloqueo
                    if(currentTime >= blockStart && currentTime <= blockEnd)
                    {
                        Print("[NEWS FILTER] Bloqueando operaciones: ", events[i].name, 
                              " a las ", TimeToString(eventTime, TIME_DATE|TIME_SECONDS));
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}
//+------------------------------------------------------------------+
//| Dibuja líneas verticales rojas en horarios de noticias fuertes   |
//+------------------------------------------------------------------+
void DrawNewsLinesOnChart()
{
    if(!EnableNewsFilter)
        return;

    MqlDateTime dt;
    TimeCurrent(dt);
    int currentHour = dt.hour;
    int currentMin = dt.min;

    // Obtener el inicio del día actual para nombres de objetos únicos
    datetime currentDayStart = GetCurrentDayStart();
    if (currentDayStart == 0) {
        Print("[ERROR] No se pudo obtener el inicio del día para dibujar líneas de noticias.");
        return;
    }

    int beforeWindow = MinsBeforeNews;
    int afterWindow = MinsAfterNews;

    // Array para almacenar las noticias en cada horario
    struct NewsEvent {
        int hour;
        int min;
        string names;
    };
    
    NewsEvent events[4];
    int eventCount = 0;

    // Definir horarios de noticias
    // 12:30 UTC - CPI, Jobless Claims
    events[0].hour = 12;
    events[0].min = 30;
    events[0].names = "CPI / Jobless Claims";

    // 13:30 UTC - NFP, PMI
    events[1].hour = 13;
    events[1].min = 30;
    events[1].names = "NFP / PMI";

    // 15:00 UTC - ISM Manufacturing
    events[2].hour = 15;
    events[2].min = 0;
    events[2].names = "ISM Manufacturing";

    // 18:00 UTC - FOMC
    events[3].hour = 18;
    events[3].min = 0;
    events[3].names = "FOMC";

    // Dibujar líneas para cada noticia dentro de la ventana de bloqueo
    for(int i = 0; i < 4; i++)
    {
        int newsHour = events[i].hour;
        int newsMin = events[i].min;
        
        MqlDateTime newsDt;
        TimeToStruct(currentDayStart, newsDt);
        newsDt.hour = newsHour;
        newsDt.min = newsMin;
        newsDt.sec = 0;
        datetime newsTime = StructToTime(newsDt);

        // Verificar si estamos en la ventana de bloqueo de esta noticia
        bool isInWindow = false;
        if(newsHour == currentHour && currentMin >= (newsMin - beforeWindow) && currentMin <= (newsMin + afterWindow))
            isInWindow = true;
        else if(newsHour - 1 == currentHour && currentMin >= (newsMin + 60 - beforeWindow))
            isInWindow = true;

        if(isInWindow)
        {
            string lineName = "NEWS_LINE_" + IntegerToString((long)currentDayStart) + "_" + IntegerToString(newsHour) + "_" + IntegerToString(newsMin);

            // Dibujar línea vertical si no existe
            if(ObjectFind(0, lineName) < 0)
            {
                ObjectCreate(0, lineName, OBJ_VLINE, 0, newsTime, 0.0);
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrBlue); // La línea azul se mantiene
                ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
                ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, lineName, OBJPROP_BACK, false);

                // Crear etiqueta con el nombre de la noticia
                string labelName = "NEWS_LABEL_" + IntegerToString((long)currentDayStart) + "_" + IntegerToString(events[i].hour) + "_" + IntegerToString(events[i].min);
                if(ObjectFind(0, labelName) < 0)
                {
                    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Anchor label at current bid price
                    ObjectCreate(0, labelName, OBJ_TEXT, 0, newsTime, price);
                    ObjectSetString(0, labelName, OBJPROP_TEXT, events[i].names); // La etiqueta de la noticia ahora es blanca
                    ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite); // La etiqueta de la noticia ahora es blanca
                    ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
                    ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LOWER);
                    ObjectSetInteger(0, labelName, OBJPROP_BACK, true);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Elimina todos los números de P&L (EVE_PROFIT_) del gráfico      |
//+------------------------------------------------------------------+
void DeleteAllProfitLabels()
{
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "EVE_PROFIT_") == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| Dibuja P&L de trades cerrados recientemente en el gráfico        |
//+------------------------------------------------------------------+
void DrawTradesResultOnChart()
{
    // Seleccionar historial reciente (últimas 24 horas)
    datetime now = TimeCurrent();
    if(!HistorySelect(now - 86400, now))
        return;

    // Primero, limpiar todas las etiquetas de P/L individual anteriores
    // para evitar duplicados cuando cambiamos a modo agregado
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "EVE_PROFIT_") == 0 && StringFind(name, "EVE_PROFIT_AGG") < 0)
            ObjectDelete(0, name);
    }

    // Recolectar datos de cierres (DEAL_ENTRY_OUT) que tienen la ganancia real
    int deals = HistoryDealsTotal();
    
    // Procesar cierres para mostrar ganancia/pérdida en cada uno
    color goldBright = C'255,215,0';  // #ffe600
    color redLoss = clrRed;

    for(int i = deals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;

        // Filtrar por símbolo y MagicNumber
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;

        // Solo procesar cierres (DEAL_ENTRY_OUT) que tienen la ganancia real
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
        datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

        // Crear una etiqueta individual para cada cierre
        string objName = "EVE_PROFIT_" + IntegerToString((int)ticket);
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_TEXT, 0, time, price);
            ObjectSetString(0, objName, OBJPROP_TEXT,
                (profit >= 0 ? "+" : "") + DoubleToString(profit, 2));
            ObjectSetInteger(0, objName, OBJPROP_COLOR,
                (profit >= 0 ? goldBright : redLoss));
            ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12);
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
            ObjectSetInteger(0, objName, OBJPROP_BACK, true);
            ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Elimina etiquetas de P&L abiertas creadas por este EA            |
//+------------------------------------------------------------------+
void DeleteOpenProfitLabels()
{
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "EVE_PROFIT_POS_") == 0 || StringFind(name, "EVE_PROFIT_AGG_") == 0)
            ObjectDelete(0, name);
    }
}

//+------------------------------------------------------------------+
//| Dibuja P&L de posiciones abiertas: por posición si es única,      |
//| o una sola etiqueta agregada por lado cuando hay serie (2+)     |
//+------------------------------------------------------------------+
void DrawOpenPositionsProfitOnChart()
{
    // Limpiar etiquetas previas específicas de posiciones abiertas
    DeleteOpenProfitLabels();

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    datetime now = TimeCurrent();

    // Procesar ambos lados: 0 -> BUY, 1 -> SELL
    for(int side = 0; side < 2; side++)
    {
        ENUM_POSITION_TYPE sideType = (side == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
        int sideCount = 0;
        double totalProfit = 0.0;
        double totalVolume = 0.0;
        double weightedPriceSum = 0.0;
        ulong lastTicket = 0;
        double lastPrice = 0.0;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!PositionBelongsToEAByIndex(i))
                continue;

            if(PositionGetInteger(POSITION_TYPE) != sideType)
                continue;

            if(PositionGetSymbol(i) != _Symbol)
                continue;

            sideCount++;
            double p = PositionGetDouble(POSITION_PROFIT);
            double vol = PositionGetDouble(POSITION_VOLUME);
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            ulong ticket = PositionGetInteger(POSITION_TICKET);

            totalProfit += p;
            totalVolume += vol;
            weightedPriceSum += (open * vol);
            lastTicket = ticket;
            lastPrice = open;
        }

        // Only show aggregated label when there is a series (2 or more positions)
        if(sideCount < 2)
            continue;

        double anchorPrice = (totalVolume > 0.0 ? (weightedPriceSum / totalVolume) : (sideType == POSITION_TYPE_BUY ? bid : ask));
        string objName = "EVE_PROFIT_AGG_" + (sideType == POSITION_TYPE_BUY ? "BUY" : "SELL");
        datetime time = now;
        string text = (sideType == POSITION_TYPE_BUY ? "BUY series: " : "SELL series: ") +
                      "pos=" + IntegerToString(sideCount) +
                      " | vol=" + DoubleToString(totalVolume, 2) +
                      " | P/L=" + (totalProfit >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(totalProfit), 2);

        if(ObjectFind(0, objName) < 0)
            ObjectCreate(0, objName, OBJ_TEXT, 0, time, anchorPrice);

        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, (totalProfit >= 0 ? clrLimeGreen : clrTomato));
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 12);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(0, objName, OBJPROP_BACK, true);
    }

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Función: Gestión de Trailing Stop Virtual (Línea Amarilla)      |
//+------------------------------------------------------------------+
void ManageVirtualTrailing()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    int buyCount = 0, sellCount = 0;
    double buyVol = 0.0, sellVol = 0.0;
    double buyWeightedPrice = 0.0, sellWeightedPrice = 0.0;
    double initialBuySL = 0.0, initialSellSL = 0.0;

    // 1. Recolectar datos de las operaciones abiertas
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i)) continue;
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double vol = PositionGetDouble(POSITION_VOLUME);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);

        if(type == POSITION_TYPE_BUY) {
            buyCount++;
            buyVol += vol;
            buyWeightedPrice += open * vol;
            if(initialBuySL == 0.0 || (sl > 0 && sl < initialBuySL)) initialBuySL = sl;
        } else if(type == POSITION_TYPE_SELL) {
            sellCount++;
            sellVol += vol;
            sellWeightedPrice += open * vol;
            if(initialSellSL == 0.0 || (sl > 0 && sl > initialSellSL)) initialSellSL = sl;
        }
    }

    // --- GESTIÓN DE COMPRAS (BUY) ---
    if(buyCount == 0) {
        VirtualLineBuy = 0.0; // Resetear si no hay compras
        ObjectDelete(0, "VIRTUAL_TRAIL_BUY");
    } else {
        double avgPriceBuy = buyWeightedPrice / buyVol;
        double targetPoints = (buyCount == 1) ? VirtualStart1 : VirtualStartN;
        
        // Iniciar la línea en el SL físico real
        if(VirtualLineBuy == 0.0) VirtualLineBuy = initialBuySL;

        // Calcular ganancia actual en puntos
        int profitPoints = (int)MathRound((bid - avgPriceBuy) / point);

        // Si alcanzamos los puntos objetivo (ej. 150)
        if(profitPoints >= targetPoints) {
            // Calcular escalones de 50 en 50
            int steps = (profitPoints - (int)targetPoints) / VirtualStep;
            // La línea asegura los primeros 50 puntos, más 50 adicionales por cada escalón subido
            double newLine = avgPriceBuy + ((VirtualStep + (steps * VirtualStep)) * point);
            
            // La línea virtual de compras solo puede moverse hacia ARRIBA
            if(newLine > VirtualLineBuy) {
                VirtualLineBuy = newLine;
            }
        }

        // Dibujar/Actualizar la línea Amarilla en el Gráfico
        if(VirtualLineBuy > 0.0) {
            if(ObjectFind(0, "VIRTUAL_TRAIL_BUY") < 0) {
                ObjectCreate(0, "VIRTUAL_TRAIL_BUY", OBJ_HLINE, 0, 0, VirtualLineBuy);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_BUY", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_BUY", OBJPROP_STYLE, STYLE_SOLID);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_BUY", OBJPROP_WIDTH, 2);
            } else {
                ObjectMove(0, "VIRTUAL_TRAIL_BUY", 0, 0, VirtualLineBuy);
            }
        }

        // Ejecutar CIERRE a Mercado si el precio retrocede y toca la línea (solo si ya estamos en ganancia)
        if(VirtualLineBuy > avgPriceBuy && bid <= VirtualLineBuy) {
            Print("[VIRTUAL SL] Línea amarilla alcanzada. Cerrando COMPRAS en ganancia.");
            ClosePositionsByType(POSITION_TYPE_BUY);
            VirtualLineBuy = 0.0;
            ObjectDelete(0, "VIRTUAL_TRAIL_BUY");
        }
    }

    // --- GESTIÓN DE VENTAS (SELL) ---
    if(sellCount == 0) {
        VirtualLineSell = 0.0; // Resetear si no hay ventas
        ObjectDelete(0, "VIRTUAL_TRAIL_SELL");
    } else {
        double avgPriceSell = sellWeightedPrice / sellVol;
        double targetPoints = (sellCount == 1) ? VirtualStart1 : VirtualStartN;
        
        // Iniciar la línea en el SL físico real
        if(VirtualLineSell == 0.0) VirtualLineSell = initialSellSL;

        // Calcular ganancia actual en puntos
        int profitPoints = (int)MathRound((avgPriceSell - ask) / point);

        // Si alcanzamos los puntos objetivo (ej. 150)
        if(profitPoints >= targetPoints) {
            int steps = (profitPoints - (int)targetPoints) / VirtualStep;
            double newLine = avgPriceSell - ((VirtualStep + (steps * VirtualStep)) * point);
            
            // La línea virtual de ventas solo puede moverse hacia ABAJO
            if(VirtualLineSell == 0.0 || newLine < VirtualLineSell || VirtualLineSell >= avgPriceSell) {
                VirtualLineSell = newLine;
            }
        }

        // Dibujar/Actualizar la línea Amarilla en el Gráfico
        if(VirtualLineSell > 0.0) {
            if(ObjectFind(0, "VIRTUAL_TRAIL_SELL") < 0) {
                ObjectCreate(0, "VIRTUAL_TRAIL_SELL", OBJ_HLINE, 0, 0, VirtualLineSell);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_SELL", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_SELL", OBJPROP_STYLE, STYLE_SOLID);
                ObjectSetInteger(0, "VIRTUAL_TRAIL_SELL", OBJPROP_WIDTH, 2);
            } else {
                ObjectMove(0, "VIRTUAL_TRAIL_SELL", 0, 0, VirtualLineSell);
            }
        }

        // Ejecutar CIERRE a Mercado si el precio retrocede y toca la línea (solo si ya estamos en ganancia)
        if(VirtualLineSell > 0.0 && VirtualLineSell < avgPriceSell && ask >= VirtualLineSell) {
            Print("[VIRTUAL SL] Línea amarilla alcanzada. Cerrando VENTAS en ganancia.");
            ClosePositionsByType(POSITION_TYPE_SELL);
            VirtualLineSell = 0.0;
            ObjectDelete(0, "VIRTUAL_TRAIL_SELL");
        }
    }
}

//+------------------------------------------------------------------+
//| Cierra todas las posiciones del EA                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i))
            continue;
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        trade.PositionClose(ticket);
    }
}

//+------------------------------------------------------------------+
//| Cierra posiciones por tipo (BUY o SELL)                         |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE posType)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i)) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType)
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            trade.PositionClose(ticket);
        }
    }
}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. Gestionar trailing stop virtual (línea amarilla)
    ManageVirtualTrailing();

    // 1.1 Borrar órdenes pendientes que ya superaron su edad máxima
    DeleteExpiredPendingOrders();

    // 2. Verificar si estamos en ventana de noticia
    bool isNewsActive = IsNewsTimeActive();

    // 3. Seguro de actualización visual: solo una vez por segundo
    static datetime lastVisualUpdateSecond = 0;
    datetime visualNow = TimeCurrent();
    bool runVisualTasks = (visualNow != lastVisualUpdateSecond);
    bool updatePanelOnly = MQLInfoInteger(MQL_TESTER) && visualNow != lastVisualUpdateSecond;

    // Estado del ciclo diario
    static datetime cycleDayStart = 0;
    static datetime lastSRRefreshOpen = 0;
    static datetime lastOrderPlacedCycleOpen = 0;
    static datetime lastProfitLabelsCleanupTime = 0;  // Para limpiar P&L cada 7 días
    static double activeSupport = 0.0;
    static double activeResistance = 0.0;
    static string activeSource = "SIN_ANALISIS";
    static string cycleStatus = "Inicializando ciclo";
    static string newsStatus = "SIN NOTICIAS";
    static string sellDecision = "Sin evaluar";
    static string buyDecision = "Sin evaluar";
    static bool sellArmed = false;
    static bool buyArmed = false;
    static bool sellLevelTouched = false;
    static bool buyLevelTouched = false;
    static double lastBid = 0.0;
    static double lastAsk = 0.0;
    datetime todayStart = GetCurrentDayStart();
    if(todayStart <= 0)
    {
        Comment("ERROR: no se pudo determinar inicio de dia");
        return;
    }

    // Limpiar etiquetas de P&L cada 7 días
    datetime now = TimeCurrent();
    if(lastProfitLabelsCleanupTime == 0)
        lastProfitLabelsCleanupTime = now;
    
    if((now - lastProfitLabelsCleanupTime) >= 604800)  // 604800 segundos = 7 días
    {
        DeleteAllProfitLabels();
        lastProfitLabelsCleanupTime = now;
        Print("[CLEANUP] Se eliminaron todas las etiquetas de P&L (más de 7 días)");
    }

    if(cycleDayStart != todayStart)
    {
        cycleDayStart = todayStart;
        lastSRRefreshOpen = 0;
        lastOrderPlacedCycleOpen = 0;
        activeSupport = 0.0;
        activeResistance = 0.0;
        activeSource = "SIN_ANALISIS";
        cycleStatus = "Nuevo dia: esperando analisis de S/R";
        sellDecision = "Pendiente analisis";
        buyDecision = "Pendiente analisis";
        sellArmed = false;
        buyArmed = false;
        sellLevelTouched = false;
        buyLevelTouched = false;

        // Eliminar líneas de noticias del día anterior al iniciar un nuevo día
        DeleteAllNewsLines();

        Print("[CYCLE] Nuevo dia iniciado. Se reinicia ciclo SR configurable");
    }

    bool tradingTimeOk = IsTradingTime();
    double currentSpreadPoints = GetCurrentSpreadPoints();
    bool spreadOk = (currentSpreadPoints <= (double)MathMax(1, MaxSpreadPoints));

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Calcular TP fijo y SL fijo
    double fixedSLDist = PointsToPriceDistance(sl_points);
    double tpDist = PointsToPriceDistance(tp_points);
    double slDist = fixedSLDist;

    if(fixedSLDist <= 0 || tpDist <= 0)
    {
        Comment("ERROR calculando SL/TP");
        return;
    }

    // Usar SL fijo en puntos
    slDist = fixedSLDist;
    bool hasOpenPosition = (CountOpenPositions() > 0);
    bool runAnalysisNow = false;
    ENUM_TIMEFRAMES srTf = GetSupportResistanceTimeframe();
    ENUM_TIMEFRAMES srRefreshTf = srTf;
    datetime currentSRRefreshOpen = iTime(_Symbol, srRefreshTf, 0);
    int srLookbackSafe = MathMax(1, SRLookbackBars);
    // Analisis de niveles al iniciar nueva vela del timeframe de refresco
    if(!EnableSR)
    {
        // Si los niveles están desactivados, limpiar niveles previos y evitar nuevo análisis
        if(activeSupport != 0.0 || activeResistance != 0.0)
        {
            DeleteAllLevelLines();
            activeSupport = 0.0;
            activeResistance = 0.0;
            activeSource = "SR_DESACTIVADO";
        }
        runAnalysisNow = false;
        cycleStatus = "S/R desactivado";
    }
    else if(currentSRRefreshOpen > 0 && currentSRRefreshOpen != lastSRRefreshOpen)
    {
        lastSRRefreshOpen = currentSRRefreshOpen;

        double srSupport = 0.0;
        double srResistance = 0.0;
        if(GetSupportResistanceLevels(srTf, srLookbackSafe, srSupport, srResistance))
        {
            activeSupport = srSupport;
            activeResistance = srResistance;
            activeSource = "SR_" + TimeframeLabel(srTf) + "_" + IntegerToString(srLookbackSafe) + "v";
            runAnalysisNow = true;
            cycleStatus = "Analisis S/R en " + TimeframeLabel(srTf) + " | Trigger " + TimeframeLabel(srRefreshTf);

            Print("[CYCLE] Nueva vela iniciada en ", TimeframeLabel(srRefreshTf),
                  ". S/R calculado en ", TimeframeLabel(srTf),
                  " con ", srLookbackSafe, " velas cerradas.");
        }
        else
        {
            cycleStatus = "Error calculando S/R en " + TimeframeLabel(srTf);
        }
    }

    if(hasOpenPosition)
    {
        cycleStatus = "Posicion abierta: solo gestion y sin nuevas entradas";
        sellArmed = false;
        buyArmed = false;
        sellLevelTouched = false;
        buyLevelTouched = false;
    }

    if(runAnalysisNow && !hasOpenPosition)
    {
        double adxValue = 0.0;
        double sellVolCurrent = 0.0;
        double sellVolAverage = 0.0;
        double buyVolCurrent = 0.0;
        double buyVolAverage = 0.0;
        double bbUpper = 0.0, bbMiddle = 0.0, bbLower = 0.0, bbWidth = 0.0;
        double vwapValue = 0.0;
        bool adxOk = PassesADXFilter(adxValue);
        bool sellVolumeOk = PassesVolumeFilter(false, sellVolCurrent, sellVolAverage);
        bool buyVolumeOk = PassesVolumeFilter(true, buyVolCurrent, buyVolAverage);
        bool sellBBOk = PassesBBFilter(false, bbUpper, bbMiddle, bbLower, bbWidth);
        bool buyBBOk = PassesBBFilter(true, bbUpper, bbMiddle, bbLower, bbWidth);
        bool sellVWAPOk = PassesVWAPFilter(false, vwapValue);
        bool buyVWAPOk = PassesVWAPFilter(true, vwapValue);

        if(!adxOk)
        {
            string adxText = DoubleToString(adxValue, 1);
            sellDecision = "SELL bloqueado por ADX bajo: " + adxText;
            buyDecision = "BUY bloqueado por ADX bajo: " + adxText;
            sellArmed = false;
            buyArmed = false;
            Print("[BLOCK] Entrada bloqueada por ADX: value=", adxText);
        }
        else
        {
            bool sellCandidate = false;
            bool buyCandidate = false;
            bool trendUp = false;
            bool trendDown = false;
            bool hasAnyPendingOrder = (CountPendingOrders() > 0);

            if(EnableEMAFilter && handleEMA != INVALID_HANDLE)
            {
                double trendEmaValue = 0.0;
                bool emaBuySide = PassesEMAFilter(true, trendEmaValue);
                bool emaSellSide = PassesEMAFilter(false, trendEmaValue);
                trendUp = (emaBuySide && !emaSellSide);
                trendDown = (emaSellSide && !emaBuySide);

                if(trendUp)
                    Print("[TREND] Tendencia alcista detectada por EMA: solo BUY habilitado");
                else if(trendDown)
                    Print("[TREND] Tendencia bajista detectada por EMA: solo SELL habilitado");
                else
                    Print("[TREND] Sin direccion clara respecto a EMA: se bloquean ambas direcciones");
            }

            if(activeSupport <= 0.0)
            {
                sellDecision = "Sin soporte valido en " + activeSource;
            }
            else
            {
                sellCandidate = true;
                sellDecision = "Sell armado en soporte detectado";
            }

            if(activeResistance <= 0.0)
            {
                buyDecision = "Sin resistencia valida en " + activeSource;
            }
            else
            {
                buyCandidate = true;
                buyDecision = "Buy armado en resistencia detectada";
            }

            if(trendUp)
            {
                sellCandidate = false;
                sellDecision = "SELL bloqueado: tendencia alcista";
            }
            else if(trendDown)
            {
                buyCandidate = false;
                buyDecision = "BUY bloqueado: tendencia bajista";
            }
            else if(EnableEMAFilter && handleEMA != INVALID_HANDLE)
            {
                sellCandidate = false;
                buyCandidate = false;
                sellDecision = "Ambas direcciones bloqueadas: EMA sin direccion clara";
                buyDecision = "Ambas direcciones bloqueadas: EMA sin direccion clara";
            }

            if(!sellVolumeOk)
            {
                sellCandidate = false;
                sellDecision = "SELL bloqueado por volumen/vela de ruptura";
                Print("[BLOCK] SELL bloqueado por volumen - current=", DoubleToString(sellVolCurrent,0), " avg=", DoubleToString(sellVolAverage,0));
            }

            if(!buyVolumeOk)
            {
                buyCandidate = false;
                buyDecision = "BUY bloqueado por volumen/vela de ruptura";
                Print("[BLOCK] BUY bloqueado por volumen - current=", DoubleToString(buyVolCurrent,0), " avg=", DoubleToString(buyVolAverage,0));
            }

            if(!sellBBOk)
            {
                sellCandidate = false;
                sellDecision = "SELL bloqueado por Bollinger Bands";
                Print("[BLOCK] SELL bloqueado por BB - bbWidth=", DoubleToString(bbWidth, _Digits));
            }

            if(!buyBBOk)
            {
                buyCandidate = false;
                buyDecision = "BUY bloqueado por Bollinger Bands";
                Print("[BLOCK] BUY bloqueado por BB - bbWidth=", DoubleToString(bbWidth, _Digits));
            }

            if(!sellVWAPOk)
            {
                sellCandidate = false;
                sellDecision = "SELL bloqueado por VWAP dinámico";
                Print("[BLOCK] SELL bloqueado por VWAP - vwap=", DoubleToString(vwapValue, _Digits), " bid=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits));
            }

            if(!buyVWAPOk)
            {
                buyCandidate = false;
                buyDecision = "BUY bloqueado por VWAP dinámico";
                Print("[BLOCK] BUY bloqueado por VWAP - vwap=", DoubleToString(vwapValue, _Digits), " ask=", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits));
            }

            if(hasAnyPendingOrder)
            {
                sellCandidate = false;
                buyCandidate = false;
                sellDecision = "Bloqueado: ya existe una orden pendiente del EA";
                buyDecision = "Bloqueado: ya existe una orden pendiente del EA";
            }

            sellArmed = sellCandidate;
            buyArmed = buyCandidate;
            sellLevelTouched = false;
            buyLevelTouched = false;
        }
    }

    if(runAnalysisNow)
    {
        // Limpiar líneas viejas de análisis anterior
        DeleteAllLevelLines();
        
        datetime markerTime = iTime(_Symbol, srTf, 1);

        if(markerTime <= 0)
            markerTime = TimeCurrent();

        DrawSupportResistanceOnChart(srTf, markerTime, activeSupport, activeResistance);
    }

    // Registro diagnóstico consolidado para entender por qué no se arma el análisis
    Print("[DIAG] runAnalysisNow=", (runAnalysisNow ? "true" : "false"),
          " | EnableSR=", (EnableSR ? "true" : "false"),
          " | lastSRRefreshOpen=", TimeToString(lastSRRefreshOpen, TIME_DATE|TIME_SECONDS),
          " | currentSRRefreshOpen=", TimeToString(currentSRRefreshOpen, TIME_DATE|TIME_SECONDS),
          " | activeSupport=", DoubleToString(activeSupport, _Digits),
          " | activeResistance=", DoubleToString(activeResistance, _Digits),
          " | sellArmed=", (sellArmed ? "true" : "false"),
          " | buyArmed=", (buyArmed ? "true" : "false"),
          " | VolEn=", (EnableVolumeFilter ? "true" : "false")
    );

    if(EnableMartingaleFollowUp && !hasOpenPosition)
    {
        static datetime lastMGNoPosLog = 0;
        if((TimeCurrent() - lastMGNoPosLog) >= 10)
        {
            Print("[MG][IDLE] Martingala activa pero sin posiciones del EA detectadas | symbol=", _Symbol,
                  " | magic=", IntegerToString(MagicNumber),
                " | id=", IdentificadorEA,
                " | positionsTotal=", IntegerToString(PositionsTotal()),
                " | ordersTotal=", IntegerToString(OrdersTotal()));
            lastMGNoPosLog = TimeCurrent();
        }
    }

    if(EnableMartingaleFollowUp && hasOpenPosition)
    {
        static datetime lastMartingaleActionTime = 0;
        static datetime lastMartingaleRejectTime = 0;
        if(lastMartingaleActionTime != TimeCurrent())
        {
            int cooldownSafe = 30;  // Usar cooldown fijo de 30 segundos
            if(cooldownSafe > 0 && (TimeCurrent() - lastMartingaleRejectTime) < cooldownSafe)
            {
                static datetime lastMGCooldownLog = 0;
                if(lastMGCooldownLog != TimeCurrent())
                {
                    Print("[MG][COOLDOWN] Esperando reintento tras rechazo por margen | remainingSec=", IntegerToString((int)(cooldownSafe - (TimeCurrent() - lastMartingaleRejectTime))));
                    lastMGCooldownLog = TimeCurrent();
                }
                return;
            }

            int maxLevelsSafe = MathMax(1, MaxMartingaleLevels);
            double minMgDist = PointsToPriceDistance(DistanciaMinimaGrid);

            int buyCount = 0;
            double buyProfit = 0.0;
            double buyLastPrice = 0.0;
            double buyLastVol = 0.0;
            double buyLastPosProfit = 0.0;
            bool hasBuySide = GetMartingaleSideStats(POSITION_TYPE_BUY, buyCount, buyProfit, buyLastPrice, buyLastVol, buyLastPosProfit);

            int sellCount = 0;
            double sellProfit = 0.0;
            double sellLastPrice = 0.0;
            double sellLastVol = 0.0;
            double sellLastPosProfit = 0.0;
            bool hasSellSide = GetMartingaleSideStats(POSITION_TYPE_SELL, sellCount, sellProfit, sellLastPrice, sellLastVol, sellLastPosProfit);

            bool martingalePlaced = false;
            static datetime lastMGDiagTime = 0;

            // Martingala BUY basada solo en distancia
            if(hasBuySide && buyCount < maxLevelsSafe)
            {
                double adverseDistBuy = buyLastPrice - bid;
                if(adverseDistBuy >= minMgDist)
                {
                    double lotMgBuyRaw = GetNextMartingaleLotFromLast(buyLastVol);
                    double requiredMarginBuy = 0.0;
                    double lotMgBuy = FitLotToMargin(true, lotMgBuyRaw, ask, requiredMarginBuy);
                    if(lotMgBuy <= 0.0)
                    {
                        Print("[MG][WAIT] BUY sin margen para nuevo nivel | requestedLot=", DoubleToString(lotMgBuyRaw, 2),
                              " | freeMargin=", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
                        lastMartingaleRejectTime = TimeCurrent();
                        return;
                    }
                    double buySL = 0.0;
                    GetSharedBasketSLPrice(POSITION_TYPE_BUY, ask, slDist, buySL);
                    double buyTP = NormalizeDouble(ask + tpDist, _Digits);
                    martingalePlaced = trade.Buy(
                        lotMgBuy,
                        _Symbol,
                        0.0,
                        buySL,
                        buyTP,
                        BuildOrderComment("MARTINGALE_BUY")
                    );

                    if(martingalePlaced)
                    {
                        lastMartingaleActionTime = TimeCurrent();
                        Print("[MG] BUY adicional abierto | lot=", DoubleToString(lotMgBuy, 2),
                              " | margin=", DoubleToString(requiredMarginBuy, 2),
                              " | adverseDist=", DoubleToString(adverseDistBuy, _Digits),
                              " | niveles=", IntegerToString(buyCount + 1), "/", IntegerToString(maxLevelsSafe));
                    }
                    else
                    {
                        Print("[MG][ERROR] BUY adicional rechazado | retcode=", IntegerToString((int)trade.ResultRetcode()),
                              " | desc=", trade.ResultRetcodeDescription());
                        if((int)trade.ResultRetcode() == 10019)
                            lastMartingaleRejectTime = TimeCurrent();
                    }
                }
                else if(lastMGDiagTime != TimeCurrent())
                {
                    Print("[MG][WAIT] BUY en pérdida pero sin distancia suficiente | dist=", DoubleToString(adverseDistBuy, _Digits),
                          " | minMGDist=", DoubleToString(minMgDist, _Digits),
                          " | DistanciaMinimaGrid=", IntegerToString(DistanciaMinimaGrid));
                    lastMGDiagTime = TimeCurrent();
                }
            }

            // Martingala SELL basada solo en distancia
            if(!martingalePlaced && hasSellSide && sellCount < maxLevelsSafe)
            {
                double adverseDistSell = ask - sellLastPrice;
                if(adverseDistSell >= minMgDist)
                {
                    double lotMgSellRaw = GetNextMartingaleLotFromLast(sellLastVol);
                    double requiredMarginSell = 0.0;
                    double lotMgSell = FitLotToMargin(false, lotMgSellRaw, bid, requiredMarginSell);
                    if(lotMgSell <= 0.0)
                    {
                        Print("[MG][WAIT] SELL sin margen para nuevo nivel | requestedLot=", DoubleToString(lotMgSellRaw, 2),
                              " | freeMargin=", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
                        lastMartingaleRejectTime = TimeCurrent();
                        return;
                    }
                    double sellSL = 0.0;
                    GetSharedBasketSLPrice(POSITION_TYPE_SELL, bid, slDist, sellSL);
                    double sellTP = NormalizeDouble(bid - tpDist, _Digits);
                    martingalePlaced = trade.Sell(
                        lotMgSell,
                        _Symbol,
                        0.0,
                        sellSL,
                        sellTP,
                        BuildOrderComment("MARTINGALE_SELL")
                    );

                    if(martingalePlaced)
                    {
                        lastMartingaleActionTime = TimeCurrent();
                        Print("[MG] SELL adicional abierto | lot=", DoubleToString(lotMgSell, 2),
                              " | margin=", DoubleToString(requiredMarginSell, 2),
                              " | adverseDist=", DoubleToString(adverseDistSell, _Digits),
                              " | niveles=", IntegerToString(sellCount + 1), "/", IntegerToString(maxLevelsSafe));
                    }
                    else
                    {
                        Print("[MG][ERROR] SELL adicional rechazado | retcode=", IntegerToString((int)trade.ResultRetcode()),
                              " | desc=", trade.ResultRetcodeDescription());
                        if((int)trade.ResultRetcode() == 10019)
                            lastMartingaleRejectTime = TimeCurrent();
                    }
                }
                else if(lastMGDiagTime != TimeCurrent())
                {
                    Print("[MG][WAIT] SELL en pérdida pero sin distancia suficiente | dist=", DoubleToString(adverseDistSell, _Digits),
                          " | minMGDist=", DoubleToString(minMgDist, _Digits),
                          " | DistanciaMinimaGrid=", IntegerToString(DistanciaMinimaGrid));
                    lastMGDiagTime = TimeCurrent();
                }
            }

            // Mejoramos el diagnóstico para saber exactamente qué falta
            if(!martingalePlaced && (TimeCurrent() - lastMGDiagTime >= 10)) // Log cada 10 segundos
            {
                if(hasBuySide) 
                   PrintFormat("[MG-INFO] BUY Serie: %d/%d | Distancia actual: %.1f / Req: %d pts", 
                                         buyCount, maxLevelsSafe, (buyLastPrice - bid)/_Point, DistanciaMinimaGrid);
                
                if(hasSellSide)
                   PrintFormat("[MG-INFO] SELL Serie: %d/%d | Distancia actual: %.1f / Req: %d pts", 
                                         sellCount, maxLevelsSafe, (ask - sellLastPrice)/_Point, DistanciaMinimaGrid);
                               
                lastMGDiagTime = TimeCurrent();
            }
        }
    }

    if(!hasOpenPosition && (sellArmed || buyArmed))
    {
        // Actualizar estado de noticias
        newsStatus = isNewsActive ? "⚠️ BLOQUEADO POR NOTICIA" : "SIN NOTICIAS";

        if(isNewsActive)
        {
            if(sellArmed) sellDecision = "Sell armado: BLOQUEADO por noticia de alto impacto";
            if(buyArmed) buyDecision = "Buy armado: BLOQUEADO por noticia de alto impacto";
        }
        else if(!tradingTimeOk)
        {
            if(sellArmed) sellDecision = "Sell armado: fuera de horario";
            if(buyArmed) buyDecision = "Buy armado: fuera de horario";
        }
        else if(!spreadOk)
        {
            if(sellArmed) sellDecision = "Sell armado: spread alto";
            if(buyArmed) buyDecision = "Buy armado: spread alto";
        }
        else if(HasMarketEntryInCurrentCycle(currentSRRefreshOpen))
        {
            if(sellArmed) sellDecision = "Sell armado: limite 1 entrada por ciclo";
            if(buyArmed) buyDecision = "Buy armado: limite 1 entrada por ciclo";
        }
        else
        {
            int entryOffsetPointsSafe = MathMax(0, EntryOffsetPoints);
            double entryOffsetDist = PointsToPriceDistance(entryOffsetPointsSafe);
            double retraceDist = PointsToPriceDistance(MathMax(0, MinRetracePoints));
            double sellEntry = NormalizeDouble(activeSupport - entryOffsetDist, _Digits);
            double buyEntry  = NormalizeDouble(activeResistance + entryOffsetDist, _Digits);
            bool usePendingStops = (EntryMode == ENTRY_MODE_PENDING_STOP);
            double entryLotBase = NormalizeLotBySymbol(LoteInicial);

            bool sellOrderPlacementDone = false;
            bool buyOrderPlacementDone = false;
            double emaValue = 0.0;
            double rsiValue = 0.0;

            if(sellArmed && activeSupport > 0.0 && CountPendingOrdersByType(ORDER_TYPE_SELL_STOP) == 0)
            {
                bool emaOkSell = PassesEMAFilter(false, emaValue);
                bool rsiOkSell = PassesRSIFilter(false, rsiValue);

                if(!emaOkSell)
                {
                    sellDecision = usePendingStops
                        ? "SELL STOP bloqueado por EMA200 H1"
                        : "SELL mercado bloqueado por EMA200 H1";
                    Print("[BLOCK] SELL bloqueado por EMA - ema=", DoubleToString(emaValue, _Digits), " mid=", DoubleToString((ask+bid)/2, _Digits));
                }
                else if(!rsiOkSell)
                {
                    sellDecision = usePendingStops
                        ? "SELL STOP bloqueado por RSI"
                        : "SELL mercado bloqueado por RSI";
                    Print("[BLOCK] SELL bloqueado por RSI - rsi=", DoubleToString(rsiValue,1));
                }
                else
                {
                    if(MinRetracePoints > 0 && bid <= (activeSupport + retraceDist))
                    {
                        sellDecision = "SELL esperando retroceso suficiente desde soporte";
                        Print("[BLOCK] SELL esperando retrace - bid=", DoubleToString(bid,_Digits), " support=", DoubleToString(activeSupport,_Digits), " retraceDist=", DoubleToString(retraceDist,_Digits));
                    }
                    else
                    {
                        if(usePendingStops && !IsValidSellStopPrice(sellEntry, bid))
                        {
                            sellDecision = "SELL STOP invalido: soporte demasiado cerca del precio";
                            Print("[BLOCK] SELL STOP invalido - sellEntry=", DoubleToString(sellEntry,_Digits), " bid=", DoubleToString(bid,_Digits));
                        }
                        else if(usePendingStops && ExistsSellStopAtPrice(sellEntry))
                        {
                            sellDecision = "SELL STOP ya existe/cercano en soporte";
                            Print("[BLOCK] SELL STOP existe cercano - sellEntry=", DoubleToString(sellEntry,_Digits));
                        }
                        else
                        {
                            // Al ser la primera orden, calculamos SL normal
                            double sellSL = NormalizeDouble(sellEntry + slDist, _Digits);
                            double sellTP = NormalizeDouble(sellEntry - tpDist, _Digits);

                            if(usePendingStops)
                            {
                                sellOrderPlacementDone = trade.SellStop(
                                    entryLotBase,
                                    sellEntry,
                                    _Symbol,
                                    sellSL,
                                    sellTP,
                                    ORDER_TIME_GTC,
                                    0,
                                    BuildOrderComment("SUPPORT_SELL_STOP")
                                );
                            }
                            else
                            {
                                bool touchedNowSell = (lastBid > 0.0 && lastBid > sellEntry && bid <= sellEntry);
                                if(touchedNowSell)
                                    sellLevelTouched = true;

                                if(!sellLevelTouched)
                                {
                                    sellDecision = "Sell armado: esperando toque en soporte";
                                }
                                else
                                {
                                    sellOrderPlacementDone = trade.Sell(
                                        entryLotBase,
                                        _Symbol,
                                        0.0,
                                        sellSL,
                                        sellTP,
                                        BuildOrderComment("SUPPORT_SELL_MARKET")
                                    );
                                }
                            }

                            if(sellOrderPlacementDone)
                            {
                                lastOrderPlacedCycleOpen = currentSRRefreshOpen;
                                sellDecision = usePendingStops
                                    ? "SELL STOP colocado al detectar soporte " + activeSource
                                    : "SELL mercado ejecutado al tocar soporte " + activeSource;
                                sellArmed = false;
                                sellLevelTouched = false;

                                Print("[ORDEN] ", (usePendingStops ? "SELL STOP" : "SELL mercado"), " colocado al detectar soporte ", activeSource,
                                      " | Nivel: ", DoubleToString(sellEntry, _Digits),
                                      " | SL: ", DoubleToString(sellSL, _Digits),
                                      " | TP: ", DoubleToString(sellTP, _Digits));
                            }
                            else
                            {
                                if(usePendingStops || sellLevelTouched)
                                {
                                    sellDecision = usePendingStops
                                        ? "Error al colocar SELL STOP"
                                        : "Error al ejecutar SELL mercado";
                                    Print("[ERROR] Failed to place ", (usePendingStops ? "SELL STOP" : "SELL market"), ". Error: ", GetLastError());
                                }
                            }
                        }
                    }
                }
            }

            if(buyArmed && activeResistance > 0.0 && CountPendingOrdersByType(ORDER_TYPE_BUY_STOP) == 0)
            {
                bool emaOkBuy = PassesEMAFilter(true, emaValue);
                bool rsiOkBuy = PassesRSIFilter(true, rsiValue);

                if(!emaOkBuy)
                {
                    buyDecision = usePendingStops
                        ? "BUY STOP bloqueado por EMA200 H1"
                        : "BUY mercado bloqueado por EMA200 H1";
                    Print("[BLOCK] BUY bloqueado por EMA - ema=", DoubleToString(emaValue, _Digits), " mid=", DoubleToString((ask+bid)/2, _Digits));
                }
                else if(!rsiOkBuy)
                {
                    buyDecision = usePendingStops
                        ? "BUY STOP bloqueado por RSI"
                        : "BUY mercado bloqueado por RSI";
                    Print("[BLOCK] BUY bloqueado por RSI - rsi=", DoubleToString(rsiValue,1));
                }
                else
                {
                    if(MinRetracePoints > 0 && ask >= (activeResistance - retraceDist))
                    {
                        buyDecision = "BUY esperando retroceso suficiente desde resistencia";
                        Print("[BLOCK] BUY esperando retrace - ask=", DoubleToString(ask,_Digits), " resistance=", DoubleToString(activeResistance,_Digits), " retraceDist=", DoubleToString(retraceDist,_Digits));
                    }
                    else
                    {
                        if(usePendingStops && !IsValidBuyStopPrice(buyEntry, ask))
                        {
                            buyDecision = "BUY STOP invalido: resistencia demasiado cerca del precio";
                            Print("[BLOCK] BUY STOP invalido - buyEntry=", DoubleToString(buyEntry,_Digits), " ask=", DoubleToString(ask,_Digits));
                        }
                        else if(usePendingStops && ExistsBuyStopAtPrice(buyEntry))
                        {
                            buyDecision = "BUY STOP ya existe/cercano en resistencia";
                            Print("[BLOCK] BUY STOP existe cercano - buyEntry=", DoubleToString(buyEntry,_Digits));
                        }
                        else
                        {
                            double buySL = NormalizeDouble(buyEntry - slDist, _Digits);
                            double buyTP = NormalizeDouble(buyEntry + tpDist, _Digits);

                            if(usePendingStops)
                            {
                                buyOrderPlacementDone = trade.BuyStop(
                                    entryLotBase,
                                    buyEntry,
                                    _Symbol,
                                    buySL,
                                    buyTP,
                                    ORDER_TIME_GTC,
                                    0,
                                    BuildOrderComment("RESISTANCE_BUY_STOP")
                                );
                            }
                            else
                            {
                                bool touchedNowBuy = (lastAsk > 0.0 && lastAsk < buyEntry && ask >= buyEntry);
                                if(touchedNowBuy)
                                    buyLevelTouched = true;

                                if(!buyLevelTouched)
                                {
                                    buyDecision = "Buy armado: esperando toque en resistencia";
                                }
                                else
                                {
                                    buyOrderPlacementDone = trade.Buy(
                                        entryLotBase,
                                        _Symbol,
                                        0.0,
                                        buySL,
                                        buyTP,
                                        BuildOrderComment("RESISTANCE_BUY_MARKET")
                                    );
                                }
                            }

                            if(buyOrderPlacementDone)
                            {
                                lastOrderPlacedCycleOpen = currentSRRefreshOpen;
                                buyDecision = usePendingStops
                                    ? "BUY STOP colocado al detectar resistencia " + activeSource
                                    : "BUY mercado ejecutado al tocar resistencia " + activeSource;
                                buyArmed = false;
                                buyLevelTouched = false;

                                Print("[ORDEN] ", (usePendingStops ? "BUY STOP" : "BUY mercado"), " colocado al detectar resistencia ", activeSource,
                                      " | Nivel: ", DoubleToString(buyEntry, _Digits),
                                      " | SL: ", DoubleToString(buySL, _Digits),
                                      " | TP: ", DoubleToString(buyTP, _Digits));
                            }
                            else
                            {
                                if(usePendingStops || buyLevelTouched)
                                {
                                    buyDecision = usePendingStops
                                        ? "Error al colocar BUY STOP"
                                        : "Error al ejecutar BUY mercado";
                                    Print("[ERROR] Failed to place ", (usePendingStops ? "BUY STOP" : "BUY market"), ". Error: ", GetLastError());
                                }
                            }
                        }
                    }
                }
            }

            if(sellArmed && !sellOrderPlacementDone)
            {
                sellDecision = usePendingStops
                    ? "Sell armado: se intentara SELL STOP en el proximo tick valido"
                    : "Sell armado: esperando toque para ejecutar mercado";
            }
            if(buyArmed && !buyOrderPlacementDone)
            {
                buyDecision = usePendingStops
                    ? "Buy armado: se intentara BUY STOP en el proximo tick valido"
                    : "Buy armado: esperando toque para ejecutar mercado";
            }
        }
    }

    lastBid = bid;
    lastAsk = ask;

    // --- Panel de información ---
    double accumulatedUSD = GetAccumulatedEAProfitUSD();
    string accumulatedStr = (accumulatedUSD >= 0.0 ? "+" : "") + DoubleToString(accumulatedUSD, 2);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double slDistPointsUsed = (point > 0.0 ? slDist / point : 0.0);
    double adxPanelValue = 0.0;
    bool hasAdxPanelValue = false;
    string adxPanelText = "OFF";
    if(EnableADXFilter)
    {
        hasAdxPanelValue = GetADXValue(adxPanelValue);
        if(hasAdxPanelValue)
            adxPanelText = DoubleToString(adxPanelValue, 1) + " (" + EnumToString(ADXTimeframe) + ")";
        else
            adxPanelText = "N/D (" + EnumToString(ADXTimeframe) + ")";
    }
    double volumeCurrentPanel = 0.0;
    double volumeAveragePanel = 0.0;
    bool hasVolumePanel = GetStandardVolumeMetrics(volumeCurrentPanel, volumeAveragePanel);
    string volumePanelText = TimeframeLabel(VolumeFilterTimeframe) + ": N/D";
    if(hasVolumePanel)
    {
        double volumeRatio = (volumeAveragePanel > 0.0 ? volumeCurrentPanel / volumeAveragePanel : 0.0);
        volumePanelText = TimeframeLabel(VolumeFilterTimeframe) + ": " + DoubleToString(volumeCurrentPanel, 0) + " / " + DoubleToString(volumeAveragePanel, 0) +
                          " (x" + DoubleToString(volumeRatio, 2) + ")" + (EnableVolumeFilter ? "" : " [OFF]");
    }
    
    double bbUpperPanel = 0.0, bbMiddlePanel = 0.0, bbLowerPanel = 0.0, bbWidthPanel = 0.0;
    string bbPanelText = "OFF";
    if(EnableBBFilter)
    {
        double bbUp[], bbMid[], bbLw[];
        int copiedUp = CopyBuffer(handleBB, 0, 0, 1, bbUp);
        int copiedMid = CopyBuffer(handleBB, 1, 0, 1, bbMid);
        int copiedLw = CopyBuffer(handleBB, 2, 0, 1, bbLw);
        if(copiedUp > 0 && copiedMid > 0 && copiedLw > 0)
        {
            bbUpperPanel = bbUp[0];
            bbMiddlePanel = bbMid[0];
            bbLowerPanel = bbLw[0];
            bbWidthPanel = bbUpperPanel - bbLowerPanel;
            bbPanelText = "Upper " + DoubleToString(bbUpperPanel, _Digits) + " | Mid " + DoubleToString(bbMiddlePanel, _Digits) + 
                          " | Lower " + DoubleToString(bbLowerPanel, _Digits);
        }
        else
        {
            bbPanelText = "N/D";
        }
    }
    string slModeText = "Fijo";
    
    string currentTime = GetFormattedCurrentTime();
    string activeMarkets = GetActiveMarketsInfo();

    string panelText = "   EA Tendencia Configurable + SR\n"
                       "=========================================\n"
                       "Hora: " + currentTime + "  |  Mercado: " + activeMarkets + "\n"
                       "=========================================\n"
                       "Modo niveles: S/R | TF: " + TimeframeLabel(srTf) + "\n"
                       "Spread: " + DoubleToString(currentSpreadPoints, 1) + " points (" + DoubleToString(GetCurrentSpreadPrice(), _Digits) + " USD)\n"
                       "Volumen: " + volumePanelText + "\n"
                       "TP acumulado: " + accumulatedStr + " USD\n"
                       "---\n"
                       "Decision Sell: " + sellDecision + "\n"
                       "Decision Buy: " + buyDecision + "\n"
                       "---\n"
                       "Lote actual: " + DoubleToString(lote, 2) + "\n"
                       "Posiciones: " + IntegerToString(CountOpenPositions()) + " | Ordenes: " + IntegerToString(CountPendingOrders()) + "\n"
                       "=========================================";

    if(runVisualTasks)
    {
        DrawNewsLinesOnChart();
        // Limpiar cualquier etiqueta de P/L en vivo (no mostrar P/L abierto)
        DeleteOpenProfitLabels();
        DrawTradesResultOnChart();
    }

    if(runVisualTasks || updatePanelOnly)
    {
        UpdateInfoPanel(panelText);
        lastVisualUpdateSecond = visualNow;
    }
}
/* --- Fin de OnTick --- */

// Implementación de GetSharedBasketSLPrice
// Busca una posición existente del mismo tipo y retorna su SL
// Si no hay, calcula un nuevo SL basado en la distancia
bool GetSharedBasketSLPrice(ENUM_POSITION_TYPE sideType, double referencePrice, double slDistance, double &slPrice)
{
    if(slDistance <= 0) return false;

    // Buscar si ya hay una posición del mismo tipo abierta
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!PositionBelongsToEAByIndex(i)) continue;
        
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == sideType)
        {
            double existingSL = PositionGetDouble(POSITION_SL);
            if(existingSL != 0.0)
            {
                slPrice = existingSL;
                return true;
            }
        }
    }

    // Si no hay posición previa, calcular nuevo SL
    if(sideType == POSITION_TYPE_BUY)
        slPrice = referencePrice - slDistance * _Point;
    else if(sideType == POSITION_TYPE_SELL)
        slPrice = referencePrice + slDistance * _Point;
    else
        return false;

    return true;
}
