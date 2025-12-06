//+------------------------------------------------------------------+
//|                                                   TestSocket.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

void OnStart()
{
   int socket = SocketCreate();
   Print("Socket created: ", socket);
   if(socket != INVALID_HANDLE) SocketClose(socket);
}
