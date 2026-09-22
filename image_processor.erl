-module(image_processor).
-export([main/1]).

%% =====================================================================
%% Punto de entrada. Por ahora solo lee la imagen de entrada y arma la
%% lista de tuplas {R,G,B}; todavia no usa pa_matriz/regiones/bordes
%% (eso se conecta cuando esté listo el resto del pipeline: division en
%% regiones, procesos y comunicación con Scheme).
%% =====================================================================
main([Nombre]) ->
    io:format("Argumentos recibidos ~p~n", [Nombre]),
    {ok, Contenido} = file:read_file(Nombre), %lee el arcihvo
    Texto = binary_to_list(Contenido), %Pasa los bits a una lista
    Tokens = string:tokens(Texto, " \n\r\t"), % lo transforma todo en un strnig para manejarlo mejor
    %io:format("~p~n", [Tokens]),
    ["P3", Ancho, Alto, Max | Pixeles] = Tokens, %Los primeros numeros de un ppm son sobre sus caracteristicas, eso es lo que sacamos aca.
    Lista_linda = lists:map(fun(X) -> list_to_integer(X) end, Pixeles), %devolvemos todo a int, es necesario pasarlo a string? hasata ahora lo pienso
    Lista_lista = agrupar(Lista_linda), %se llama lista_lista porque es una lista que ya esta lista para usarse jajaja yo si soy gracioso.
    %io:format("Ancho: ~p~n", [Ancho]),
    %io:format("Alto: ~p~n", [Alto]),
    %io:format("Max: ~p~n", [Max]),
    %io:format("Pixeles: ~p~n", [Lista_lista]),
    %conectamos con scheme
    %% TODO: esto todavia no manda nada real a Scheme (protocolo sin definir).
    Resultado = os:cmd("racket prueba.rkt"),
    io:format("Scheme respondio ~s~n", [Resultado]).

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
%% Por ahora, como Scheme todavia no esta conectado, en vez de difuminar
%% de verdad solo recorta el halo (placeholder identidad) -- sirve para
%% probar division/reconstruccion antes de meter Scheme.
%% TODO: reemplazar el recorte por la llamada real a Scheme, mandandole
%% Submatriz + kernel y recibiendo la region ya filtrada.
%% Le manda al padre {resultado, Ini, FilasRecortadas} para que el
%% padre sepa a que region corresponde esta respuesta.
%% ---------------------------------------------------------------------
trabajador(Padre, Ini, Radio, Submatriz) ->
    FilasRecortadas = lists:sublist(Submatriz, Radio + 1, length(Submatriz) - 2 * Radio),
    Padre ! {resultado, Ini, FilasRecortadas}.
