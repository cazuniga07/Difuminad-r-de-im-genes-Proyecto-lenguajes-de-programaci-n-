-module(image_processor).
-export([main/1]).

%% =====================================================================
%% Punto de entrada. Uso: image_processor Entrada Salida N
%% Lee el PPM, arma la matriz, la divide en N regiones con halo, las
%% procesa en paralelo (por ahora con el placeholder de trabajador/4,
%% ver TODO ahi) y escribe la imagen reconstruida.
%% =====================================================================
main([Entrada, Salida, NStr]) ->
    N = list_to_integer(NStr),
    {ok, Contenido} = file:read_file(Entrada), %lee el arcihvo
    Texto = binary_to_list(Contenido), %Pasa los bits a una lista
    Tokens = string:tokens(Texto, " \n\r\t"), % lo transforma todo en un strnig para manejarlo mejor
    ["P3", AnchoStr, AltoStr, MaxStr | PixelesStr] = Tokens, %Los primeros numeros de un ppm son sobre sus caracteristicas, eso es lo que sacamos aca.
    Ancho = list_to_integer(AnchoStr),
    Alto = list_to_integer(AltoStr),
    Max = list_to_integer(MaxStr),
    Lista_linda = lists:map(fun(X) -> list_to_integer(X) end, PixelesStr), %devolvemos todo a int, es necesario pasarlo a string? hasata ahora lo pienso
    Lista_lista = agrupar(Lista_linda), %se llama lista_lista porque es una lista que ya esta lista para usarse jajaja yo si soy gracioso.

    Matriz = pa_matriz(Lista_lista, Ancho),
    Radio = 1, % radio del kernel 3x3 obligatorio
    Regiones = dividir(Matriz, Radio, Alto, N),
    Resultados = procesar_paralelo(Regiones, Radio),
    MatrizFinal = reconstruir(Resultados),
    escribir_ppm(Salida, Ancho, Alto, Max, MatrizFinal).

%% ---------------------------------------------------------------------
%% agrupar/1: convierte la lista plana de enteros [R,G,B,R,G,B,...]
%% (tal como viene del PPM) en una lista de tuplas de pixel {R,G,B}.
%% ---------------------------------------------------------------------
agrupar([]) -> [];
agrupar([R, G, B | T]) -> [{R, G, B} | agrupar(T)].

%% ---------------------------------------------------------------------
%% split/2: reimplementación de lists:split/2. Separa los primeros N
%% elementos de una lista del resto, sin alterar el orden original.
%% split(N, Lista) -> {PrimerosN, Resto}.
%% ---------------------------------------------------------------------
split(0, L) -> {[], L};
split(N, [H | T]) ->
    {A, B} = split(N - 1, T),
    {[H | A], B}.

%% ---------------------------------------------------------------------
%% pa_matriz/2: convierte la lista plana de tuplas {R,G,B} en una
%% matriz (lista de filas), usando el ancho de la imagen para saber
%% dónde corta cada fila.
%% ---------------------------------------------------------------------
pa_matriz([], _) -> [];
pa_matriz(P, Ancho) ->
    {Grupo, Resto} = split(Ancho, P),
    [Grupo | pa_matriz(Resto, Ancho)].

%% ---------------------------------------------------------------------
%% bordes/3: acceso seguro a una fila de la matriz por índice
%% 0-indexado. Si el índice se pasa por abajo (negativo) o por arriba
%% (>= Alto), repite la fila más cercana (estrategia de borde "repetir
%% el pixel más cercano") en vez de fallar.
%% ---------------------------------------------------------------------
bordes(Matriz, Indice, Alto) when Indice >= Alto ->
    lists:nth(Alto, Matriz);
bordes([H | _T], Indice, _Alto) when Indice < 0 ->
    H;
bordes(Matriz, Indice, _Alto) ->
    lists:nth(Indice + 1, Matriz).

%% ---------------------------------------------------------------------
%% regiones/4: calcula, para cada uno de los N procesos, el rango de
%% filas [Ini, Fin] (0-indexado) que le corresponde como región propia
%% (todavía sin halo). El sobrante de la división Alto/N se lo lleva
%% completo la última región.
%% regiones(Ini, N, TamBase, Sobra) -> [[Ini,Fin], ...]
%% ---------------------------------------------------------------------
regiones(Ini, 1, TamBase, Sobra) ->
    [[Ini, Ini + TamBase + Sobra - 1]];
regiones(Ini, N, TamBase, Sobra) ->
    Fin = Ini + TamBase - 1,
    [[Ini, Fin] | regiones(Fin + 1, N - 1, TamBase, Sobra)].


%% ---------------------------------------------------------------------
%% submatriz/4: arma la region completa CON halo que le toca mandar a
%% un proceso: junta las filas desde Ini-Radio hasta Fin+Radio, usando
%% bordes/3 para traer cada una (asi los extremos de la imagen quedan
%% cubiertos con la fila repetida en vez de reventar).
%% submatriz(Matriz, Radio, Alto, [Ini, Fin]) -> [Fila, ...]
%% ---------------------------------------------------------------------
submatriz(Matriz, Radio, Alto, [Ini, Fin]) ->
    Rango = lists:seq(Ini - Radio, Fin + Radio),
    [bordes(Matriz, X, Alto) || X <- Rango].

%% ---------------------------------------------------------------------
%% dividir/4: junta todo el Paso 2. Calcula el tamano de cada region,
%% pide los rangos con regiones/4, y arma la submatriz (con halo) de
%% cada una. Devuelve una lista de pares [Ini, Submatriz] -- se guarda
%% el Ini de cada region porque hace falta despues, para reordenar los
%% resultados que vuelvan de los procesos (pueden llegar en cualquier
%% orden).
%% dividir(Matriz, Radio, Alto, N) -> [[Ini, Submatriz], ...]
%% ---------------------------------------------------------------------
dividir(Matriz, Radio, Alto, N) ->
    TamBase = Alto div N,
    Sobra = Alto rem N,
    Regiones = regiones(0, N, TamBase, Sobra),
    [[Ini, submatriz(Matriz, Radio, Alto, [Ini, Fin])] || [Ini, Fin] <- Regiones].

%% ---------------------------------------------------------------------
%% trabajador/4: codigo que corre DENTRO de cada proceso hijo (Paso 3).
%% Por ahora, mientras armamos el protocolo con Scheme, solo recorta el
%% halo (placeholder identidad) -- sirve para probar division/
%% reconstruccion. TODO: reemplazar por la llamada real a Scheme.
%% ---------------------------------------------------------------------
trabajador(Padre, Ini, Radio, Submatriz) ->
    FilasRecortadas = lists:sublist(Submatriz, Radio + 1, length(Submatriz) - 2 * Radio),
    Padre ! {resultado, Ini, FilasRecortadas}.

%% ---------------------------------------------------------------------
%% procesar_paralelo/2: crea un proceso (spawn) por cada region de
%% ListaDeRegiones (la salida de dividir/4) y espera todos los
%% resultados. Como corren en paralelo, pueden terminar en cualquier
%% orden -- por eso cada uno vuelve etiquetado con su Ini.
%% procesar_paralelo([[Ini,Submatriz],...], Radio) -> [{Ini,Filas}, ...]
%% ---------------------------------------------------------------------
procesar_paralelo(ListaDeRegiones, Radio) ->
    Padre = self(),
    lists:foreach(
        fun([Ini, Submatriz]) ->
            spawn(fun() -> trabajador(Padre, Ini, Radio, Submatriz) end)
        end,
        ListaDeRegiones
    ),
    recolectar(length(ListaDeRegiones)).

%% recolectar/1: junta Cantidad mensajes {resultado, Ini, Filas} de la
%% casilla de correo, sin importar el orden en que lleguen.
%% TODO: cuando trabajador/4 hable con Scheme de verdad, va a poder
%% avisar tambien un {error, Ini, Motivo} -- hay que manejarlo aca para
%% no dejar pasar una region fallida en silencio.
recolectar(0) -> [];
recolectar(Cantidad) ->
    receive
        {resultado, Ini, Filas} ->
            [{Ini, Filas} | recolectar(Cantidad - 1)]
    end.

%% ---------------------------------------------------------------------
%% reconstruir/1: ordena los resultados por Ini (deshace el desorden
%% de la concurrencia) y concatena todas las filas en una sola matriz.
%% ---------------------------------------------------------------------
reconstruir(Resultados) ->
    Ordenados = lists:keysort(1, Resultados),
    lists:append([Filas || {_Ini, Filas} <- Ordenados]).

%% ---------------------------------------------------------------------
%% escribir_ppm/5: escribe la matriz final como un archivo PPM P3.
%% ---------------------------------------------------------------------
escribir_ppm(Salida, Ancho, Alto, Max, Matriz) ->
    Cabecera = io_lib:format("P3~n~p ~p~n~p~n", [Ancho, Alto, Max]),
    Pixeles = lists:append(Matriz),
    Cuerpo = [io_lib:format("~p ~p ~p~n", [R, G, B]) || {R, G, B} <- Pixeles],
    ok = file:write_file(Salida, [Cabecera, Cuerpo]).


fila_a_texto(Fila) ->
    Pixeles = [io_lib:format("~p ~p ~p ", [R, G, B]) || {R, G, B} <- Fila],
    [Pixeles, "\n"].



escribir_entrada_region(Archivo, Radio, Submatriz) ->
    Radio2 = io_lib:format("~p~n", [Radio]),
    Cuerpo = [fila_a_texto(X) || X <- Submatriz], 
    ok = file:write_file(Archivo, [Radio2, Cuerpo]).



fila_a_texto_gauss(Fila) ->
    RGB = [io_lib:format("~p ", [A]) || A <- Fila],
    [RGB, "\n"].


kernel_gaussiano() -> [[1, 2, 1], [2, 4, 2], [1, 2, 1]].


escribir_kernel(Archivo, Kernel) ->
    Cuerpo = [fila_a_texto_gauss(X) || X <- Kernel], 
    ok = file:write_file(Archivo, Cuerpo).
