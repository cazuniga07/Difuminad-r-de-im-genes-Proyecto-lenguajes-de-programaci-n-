-module (image_processor).
-export([main/1]).

main([Nombre]) -> io:format("Argumentos recibidos ~p~n",[Nombre]), 
{ok,Contenido} = file:read_file(Nombre), %lee el arcihvo
Texto  = binary_to_list(Contenido), %Pasa los bits a una lista
Tokens = string:tokens(Texto, " \n\r\t"), % lo transforma todo en un strnig para manejarlo mejor
%io:format("~p~n", [Tokens]),
["P3",Ancho, Alto, Max | Pixeles] = Tokens, %Los primeros numeros de un ppm son sobre sus caracteristicas, eso es lo que sacamos aca.
Lista_linda = lists:map(fun(X) -> list_to_integer(X) end, Pixeles),%devolvemos todo a int, es necesario pasarlo a string? hasata ahora lo pienso
Lista_lista = agrupar(Lista_linda), %se llama lista_lista porque es una lista que ya esta lista para usarse jajaja yo si soy gracioso.
%io:format("Ancho: ~p~n", [Ancho]),
%io:format("Alto: ~p~n", [Alto]),
%io:format("Max: ~p~n", [Max]),
%io:format("Pixeles: ~p~n", [Lista_lista]),
%conectamos con scheme
Resultado = os:cmd("racket prueba.rkt"),
io:format("Scheme respondio ~s~n",[Resultado]).

agrupar([]) -> [];
agrupar([R,G,B| T]) -> [{R,G,B}|agrupar(T)]. %agrupa la vara en tuplas

