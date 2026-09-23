-module(image_processor).
-export([main/1]).

%% =====================================================================
%% Punto de entrada. Uso: image_processor Entrada Salida N
%% Lee el PPM, arma la matriz, la divide en N regiones con halo, las
%% procesa en paralelo (cada una habla con su propia instancia de
%% Scheme via llamar_scheme/4) y escribe la imagen reconstruida.
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

    Kernel = kernel_gaussiano(),
    ArchivoKernel = "kernel.txt",
    escribir_kernel(ArchivoKernel, Kernel), % se escribe una sola vez, es igual para todas las regiones
    Matriz = pa_matriz(Lista_lista, Ancho),
    Radio = 1, % radio del kernel 3x3 obligatorio
    Regiones = dividir(Matriz, Radio, Alto, N),
    Resultados = procesar_paralelo(Regiones, Radio, ArchivoKernel),
    MatrizFinal = reconstruir(Resultados),
    escribir_ppm(Salida, Ancho, Alto, Max, MatrizFinal).

%% =======================================================================
%% Lectura de la imagen y armado de la matriz.
%% =======================================================================

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

%% =======================================================================
%% Division de la imagen en regiones con halo.
%% =======================================================================

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
    N2 = min(Alto, N), % nunca mas regiones que filas tiene la imagen
    TamBase = Alto div N2,
    Sobra = Alto rem N2,
    Regiones = regiones(0, N2, TamBase, Sobra),
    [[Ini, submatriz(Matriz, Radio, Alto, [Ini, Fin])] || [Ini, Fin] <- Regiones].

%% =======================================================================
%% Protocolo de comunicacion con Scheme (archivos de texto, uno por
%% region, mas uno para el kernel -- compartido por todas las regiones).
%% Cada archivo se lee completo hasta EOF, sin declarar cuantas filas
%% tiene, porque cada bloque de datos vive en su propio archivo.
%% =======================================================================

%% ---------------------------------------------------------------------
%% kernel_gaussiano/0: kernel 3x3 obligatorio, sin normalizar (Scheme
%% divide entre la suma de los pesos, 16 en este caso).
%% ---------------------------------------------------------------------
kernel_gaussiano() -> [[1, 2, 1], [2, 4, 2], [1, 2, 1]].

%% ---------------------------------------------------------------------
%% fila_a_texto/1: [{R,G,B}, ...] -> iolist "R G B R G B ...\n"
%% (una fila de PIXELES, para el archivo de region)
%% ---------------------------------------------------------------------
fila_a_texto(Fila) ->
    Pixeles = [io_lib:format("~p ~p ~p ", [R, G, B]) || {R, G, B} <- Fila],
    [Pixeles, "\n"].

%% ---------------------------------------------------------------------
%% escribir_entrada_region/3: escribe el archivo que le toca leer a
%% Scheme para UNA region: primera linea el Radio, despues cada fila
%% de la Submatriz (que ya incluye el halo de arriba/abajo).
%% ---------------------------------------------------------------------
escribir_entrada_region(Archivo, Radio, Submatriz) ->
    Radio2 = io_lib:format("~p~n", [Radio]),
    Cuerpo = [fila_a_texto(X) || X <- Submatriz],
    ok = file:write_file(Archivo, [Radio2, Cuerpo]).

%% ---------------------------------------------------------------------
%% fila_a_texto_gauss/1: [N, ...] -> iolist "N N N ...\n"
%% (una fila de NUMEROS sueltos, para el archivo del kernel -- funciona
%% para cualquier tamano de fila, no solo 3, por si el kernel cambia)
%% ---------------------------------------------------------------------
fila_a_texto_gauss(Fila) ->
    RGB = [io_lib:format("~p ", [A]) || A <- Fila],
    [RGB, "\n"].

%% ---------------------------------------------------------------------
%% escribir_kernel/2: escribe el archivo del kernel -- generica, le
%% sirve a cualquier kernel que se le pase (no solo al gaussiano de
%% kernel_gaussiano/0), por si en la defensa piden cambiar el tamano.
%% ---------------------------------------------------------------------
escribir_kernel(Archivo, Kernel) ->
    Cuerpo = [fila_a_texto_gauss(X) || X <- Kernel],
    ok = file:write_file(Archivo, Cuerpo).

%% ---------------------------------------------------------------------
%% linea_a_fila/1: texto de UNA linea del archivo de salida de Scheme
%% ("R G B R G B ...") -> fila de tuplas {R,G,B}.
%% ---------------------------------------------------------------------
linea_a_fila(Linea) ->
    Numeros = [list_to_integer(X) || X <- string:tokens(Linea, " ")],
    agrupar(Numeros).

%% ---------------------------------------------------------------------
%% leer_salida_scheme/1: lee el archivo que escribio Scheme (una fila
%% procesada por linea, sin halo, hasta EOF) y lo convierte de vuelta
%% en una matriz (lista de filas de tuplas {R,G,B}).
%% ---------------------------------------------------------------------
leer_salida_scheme(Archivo) ->
    {ok, Contenido} = file:read_file(Archivo),
    Texto = binary_to_list(Contenido),
    Lineas = string:tokens(Texto, "\n"),
    [linea_a_fila(L) || L <- Lineas].

%% ---------------------------------------------------------------------
%% llamar_scheme/4: ejecuta una instancia de Racket para procesar UNA
%% region. Escribe su archivo de entrada (region+radio), corre el
%% script con open_port (para leer su codigo de salida real), y si
%% salio bien lee el archivo de resultado. Nunca deja pasar un fallo
%% en silencio: devuelve {ok, Filas} o {error, Motivo}.
%% ---------------------------------------------------------------------
llamar_scheme(Ini, Radio, Submatriz, ArchivoKernel) ->
    ArchivoRegion = "region_" ++ integer_to_list(Ini) ++ ".txt",
    ArchivoSalida = "salida_" ++ integer_to_list(Ini) ++ ".txt",
    escribir_entrada_region(ArchivoRegion, Radio, Submatriz),

    Comando = "racket filtro.rkt " ++ ArchivoRegion ++ " " ++ ArchivoKernel ++ " " ++ ArchivoSalida,
    Puerto = open_port({spawn, Comando}, [exit_status]),
    Codigo = receive
        {Puerto, {exit_status, C}} -> C
    end,

    file:delete(ArchivoRegion),

    case Codigo of
        0 ->
            Filas = leer_salida_scheme(ArchivoSalida),
            file:delete(ArchivoSalida),
            {ok, Filas};
        _ ->
            {error, {scheme_termino_con_codigo, Codigo}}
    end.

%% =======================================================================
%% Concurrencia: un proceso Erlang por region.
%% =======================================================================

%% ---------------------------------------------------------------------
%% trabajador/5: codigo que corre DENTRO de cada proceso hijo (Paso 3).
%% Le pide a llamar_scheme/4 que procese la region de verdad, y le
%% manda el resultado (o el error) al padre, etiquetado con Ini.
%% ---------------------------------------------------------------------
trabajador(Padre, Ini, Radio, Submatriz, ArchivoKernel) ->
    case llamar_scheme(Ini, Radio, Submatriz, ArchivoKernel) of
        {ok, Filas} -> Padre ! {resultado, Ini, Filas};
        {error, Motivo} -> Padre ! {error, Ini, Motivo}
    end.

%% ---------------------------------------------------------------------
%% procesar_paralelo/3: crea un proceso (spawn) por cada region de
%% ListaDeRegiones (la salida de dividir/4) y espera todos los
%% resultados. Como corren en paralelo, pueden terminar en cualquier
%% orden -- por eso cada uno vuelve etiquetado con su Ini.
%% procesar_paralelo([[Ini,Submatriz],...], Radio, ArchivoKernel) ->
%%   [{Ini,Filas}, ...]
%% ---------------------------------------------------------------------
procesar_paralelo(ListaDeRegiones, Radio, ArchivoKernel) ->
    Padre = self(),
    lists:foreach(
        fun([Ini, Submatriz]) ->
            spawn(fun() -> trabajador(Padre, Ini, Radio, Submatriz, ArchivoKernel) end)
        end,
        ListaDeRegiones
    ),
    recolectar(length(ListaDeRegiones)).

%% recolectar/1: junta Cantidad mensajes {resultado, Ini, Filas} de la
%% casilla de correo, sin importar el orden en que lleguen. Si algun
%% proceso avisa {error, Ini, Motivo}, se corta ahi mismo -- no se deja
%% pasar en silencio una region fallida (requisito de tolerancia a
%% fallos).
recolectar(0) -> [];
recolectar(Cantidad) ->
    receive
        {resultado, Ini, Filas} ->
            [{Ini, Filas} | recolectar(Cantidad - 1)];
        {error, Ini, Motivo} ->
            io:format("ERROR: la region que empieza en la fila ~p fallo: ~p~n", [Ini, Motivo]),
            erlang:error({region_fallida, Ini, Motivo})
    end.

%% =======================================================================
%% Reconstruccion y escritura de la imagen de salida.
%% =======================================================================

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
