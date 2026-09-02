-module (image_processor).
-export([main/1]).

main([Nombre]) -> io:format("Argumentos recibidos ~p~n",[Nombre]),
{ok,Contenido} = file:read_file(Nombre),
Texto  = binary_to_list(Contenido),
Tokens = string:tokens(Texto, " \n\r\t"),
io:format("~p~n", [Tokens]),
["P3",Ancho, Alto, Max | Pixeles] = Tokens,
Lista_linda = lists:map(fun(X) -> list_to_integer(X) end, Pixeles),
Lista_lista = agrupar(Lista_linda), %se llama lista_lista porque es una lista que ya esta lista para usarse jajaja yo si soy gracioso.
io:format("Ancho: ~p~n", [Ancho]),
io:format("Alto: ~p~n", [Alto]),
io:format("Max: ~p~n", [Max]),
io:format("Pixeles: ~p~n", [Lista_lista]).

agrupar([]) -> [];
agrupar([R,G,B| T]) -> [{R,G,B}|agrupar(T)].