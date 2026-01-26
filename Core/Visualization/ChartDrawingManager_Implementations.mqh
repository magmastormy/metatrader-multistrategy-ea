
//+------------------------------------------------------------------+
//| Draw Equal Highs                                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawEqualHighs(datetime time1, datetime time2, datetime time3, double price)
{
    // Draw liquidity line
    if(!DrawLiquidityLevel(time1, time3, price, "EQH", false))
        return false;
    
    // Draw markers
    ObjectCreate(m_chartID, GenerateObjectName("EQH_M1", TimeToString(time1)), OBJ_ARROW_STOP, 0, time1, price);
    ObjectCreate(m_chartID, GenerateObjectName("EQH_M2", TimeToString(time2)), OBJ_ARROW_STOP, 0, time2, price);
    
    if(time3 > time2)
        ObjectCreate(m_chartID, GenerateObjectName("EQH_M3", TimeToString(time3)), OBJ_ARROW_STOP, 0, time3, price);
        
    return true;
}

//+------------------------------------------------------------------+
//| Draw Equal Lows                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawEqualLows(datetime time1, datetime time2, datetime time3, double price)
{
    // Draw liquidity line
    if(!DrawLiquidityLevel(time1, time3, price, "EQL", false))
        return false;
    
    // Draw markers
    ObjectCreate(m_chartID, GenerateObjectName("EQL_M1", TimeToString(time1)), OBJ_ARROW_CHECK, 0, time1, price);
    ObjectCreate(m_chartID, GenerateObjectName("EQL_M2", TimeToString(time2)), OBJ_ARROW_CHECK, 0, time2, price);
    
    if(time3 > time2)
        ObjectCreate(m_chartID, GenerateObjectName("EQL_M3", TimeToString(time3)), OBJ_ARROW_CHECK, 0, time3, price);
        
    return true;
}

//+------------------------------------------------------------------+
//| Draw Wave Count                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveCount(datetime time, double price, int waveNumber, bool isImpulse)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;
        
    string label = IntegerToString(waveNumber);
    return DrawWaveLabel(time, price, label, isImpulse);
}

//+------------------------------------------------------------------+
//| Draw Wave Label                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveLabel(datetime time, double price, const string label, bool isImpulse)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;
    
    // Check for "Debug" label if not in debug mode
    if(StringFind(label, "Debug") >= 0 && !m_config.enableDebugMode)
        return false;
        
    string objName = GenerateObjectName("WAVE", label + "_" + TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, objName, OBJPROP_TEXT, label);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, isImpulse ? COLOR_SCHEME_ELLIOTT_IMPULSE : COLOR_SCHEME_ELLIOTT_CORRECTIVE);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Projection                                       |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawFibProjection(datetime time1, double price1, datetime time2, double price2, datetime time3, double price3)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;
        
    string objName = GenerateObjectName("FIB_EXP", TimeToString(time3));
    
    if(ObjectCreate(m_chartID, objName, OBJ_EXPANSION, 0, time1, price1, time2, price2))
    {
        ObjectSetInteger(m_chartID, objName, OBJPROP_TIME, 2, time3);
        ObjectSetDouble(m_chartID, objName, OBJPROP_PRICE, 2, price3);
        ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, clrDarkGray);
        ObjectSetInteger(m_chartID, objName, OBJPROP_LEVELS, 3);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 0, 0.618);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 1, 1.0);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 2, 1.618);
        
        m_objectsDrawn++;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Draw Exit Signal                                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawExitSignal(datetime time, double price, bool wasProfit, const string reason)
{
    if(!m_config.enableDrawing || !m_config.enableSignalMarkers)
        return false;
        
    string objName = GenerateObjectName("EXIT", TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ARROWCODE, 251); // X sign
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, wasProfit ? clrLime : clrRed);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    
    if(reason != "")
    {
        string labelName = objName + "_LABEL";
        ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
        ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, reason);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_TOP);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
    }
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Stop Loss Level                                            |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawStopLoss(datetime time, double price, bool isForBuy)
{
    return DrawHorizontalLevel(price, clrRed, "SL", STYLE_SOLID, 1, true);
}

//+------------------------------------------------------------------+
//| Draw Take Profit Level                                          |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTakeProfit(datetime time, double price, bool isForBuy, int level)
{
    return DrawHorizontalLevel(price, clrGreen, "TP" + IntegerToString(level), STYLE_DASH, 1, true);
}

//+------------------------------------------------------------------+
//| Draw Trend Line                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTrendLine(datetime time1, double price1, datetime time2, double price2,
                      color lineColor, int width, ENUM_LINE_STYLE style)
{
    if(!m_config.enableDrawing || !m_config.enableTrendLines)
        return false;
        
    string objName = GenerateObjectName("TL", TimeToString(time2));
    
    ObjectCreate(m_chartID, objName, OBJ_TREND, 0, time1, price1, time2, price2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, width);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, style);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, true);
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Text Label                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTextLabel(datetime time, double price, const string text,
                      color textColor, int fontSize, ENUM_ANCHOR_POINT anchor)
{
    if(!m_config.enableDrawing)
        return false;
        
    string objName = GenerateObjectName("TXT", text + "_" + TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, objName, OBJPROP_TEXT, text);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, textColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ANCHOR, anchor);
    
    m_objectsDrawn++;
    return true;
}
