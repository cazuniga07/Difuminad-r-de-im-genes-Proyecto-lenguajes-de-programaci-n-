-module (image_processor).
-export([main/1]).

main([Nombre]) -> io:format("Argumentos recibidos ~p~n",[Nombre]),
{ok,Contenido} = file:read_file(Nombre),
Texto  = binary_to_list(Contenido),
Tokens = string:tokens(Texto, " \n\r\t"),
io:format("~p~n", [Tokens]),
["P3",Ancho, Alto, Max | Pixeles] = Tokens,
io:format("Ancho: ~p~n", [Ancho]),
io:format("Alto: ~p~n", [Alto]),
io:format("Max: ~p~n", [Max]),
io:format("Pixeles: ~p~n", [Pixeles]).

Agrupar([]) -> [];
Agrupar([R,G,B| T]) -> [{R,G,B}|Agrupar(T)].