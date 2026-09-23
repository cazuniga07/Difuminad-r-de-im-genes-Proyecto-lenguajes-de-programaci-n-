-module(image_processor).
-export([main/1]).

%% =====================================================================
%% Punto de entrada. Uso: image_processor Entrada Salida N [Filtro]
%% Filtro es opcional, por defecto "gaussian" (el obligatorio). El
%% resto del pipeline (lectura, division en regiones, concurrencia,
%% protocolo con Scheme, reconstruccion) es identico sin importar el
%% filtro elegido -- Scheme es quien decide que hacer con Filtro.
%% =====================================================================
main([Entrada, Salida, NStr]) ->
    main([Entrada, Salida, NStr, "gaussian"]);
main([Entrada, Salida, NStr, Filtro]) ->
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
    Radio = 10, % radio del kernel 3x3 obligatorio
    Regiones = dividir(Matriz, Radio, Alto, N),
    Resultados = procesar_paralelo(Regiones, Radio, ArchivoKernel, Ancho, Filtro),
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
%% kernel_gaussiano/1: kernel (2*Radio+1)x(2*Radio+1), aproximacion
%% binomial de la gaussiana, sin normalizar. La suma de los pesos es
%% 2^(4*Radio): 16 con Radio=1, 2^40 con Radio=10.
%% ---------------------------------------------------------------------
kernel_gaussiano(Radio) ->
    Fila = fila_pascal(2 * Radio),
    producto_exterior(Fila, Fila).

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
%% leer_salida_scheme/2: lee el archivo que escribio Scheme, sin
%% importar si vino en una sola linea o en varias -- tokeniza tratando
%% espacio y salto de linea por igual, agrupa en tuplas {R,G,B}, y usa
%% Ancho (ya conocido de antemano, del PPM original) para volver a
%% cortarlo en filas con pa_matriz/2 -- la misma herramienta que ya se
%% usa para la imagen de entrada. Asi no depende de que Scheme respete
%% "una fila por linea".
%% ---------------------------------------------------------------------
leer_salida_scheme(Archivo, Ancho) ->
    {ok, Contenido} = file:read_file(Archivo),
    Texto = binary_to_list(Contenido),
    Tokens = string:tokens(Texto, " \n\r\t"),
    Numeros = [list_to_integer(X) || X <- Tokens],
    Pixeles = agrupar(Numeros),
    pa_matriz(Pixeles, Ancho).

%% ---------------------------------------------------------------------
%% llamar_scheme/6: ejecuta una instancia de Racket para procesar UNA
%% region con el filtro indicado. Escribe su archivo de entrada
%% (region+radio), corre el script con open_port (para leer su codigo
%% de salida real), y si salio bien lee el archivo de resultado. Nunca
%% deja pasar un fallo en silencio: devuelve {ok, Filas} o
%% {error, Motivo}.
%% ---------------------------------------------------------------------
llamar_scheme(Ini, Radio, Submatriz, ArchivoKernel, Ancho, Filtro) ->
    ArchivoRegion = "region_" ++ integer_to_list(Ini) ++ ".txt",
    ArchivoSalida = "salida_" ++ integer_to_list(Ini) ++ ".txt",
    escribir_entrada_region(ArchivoRegion, Radio, Submatriz),

    Comando = "racket filtro.rkt " ++ ArchivoRegion ++ " " ++ ArchivoKernel ++ " " ++ ArchivoSalida ++ " " ++ Filtro,
    Puerto = open_port({spawn, Comando}, [exit_status]),
    Codigo = receive
        {Puerto, {exit_status, C}} -> C
    end,

    file:delete(ArchivoRegion),

    case Codigo of
        0 ->
            Filas = leer_salida_scheme(ArchivoSalida, Ancho),
            file:delete(ArchivoSalida),
            {ok, Filas};
        _ ->
            {error, {scheme_termino_con_codigo, Codigo}}
    end.

%% =======================================================================
%% Concurrencia: un proceso Erlang por region.
%% =======================================================================

%% ---------------------------------------------------------------------
%% trabajador/7: codigo que corre DENTRO de cada proceso hijo (Paso 3).
%% Le pide a llamar_scheme/6 que procese la region de verdad, y le
%% manda el resultado (o el error) al padre, etiquetado con Ini.
%% ---------------------------------------------------------------------
trabajador(Padre, Ini, Radio, Submatriz, ArchivoKernel, Ancho, Filtro) ->
    case llamar_scheme(Ini, Radio, Submatriz, ArchivoKernel, Ancho, Filtro) of
        {ok, Filas} -> Padre ! {resultado, Ini, Filas};
        {error, Motivo} -> Padre ! {error, Ini, Motivo}
    end.

%% ---------------------------------------------------------------------
%% procesar_paralelo/5: crea un proceso (spawn) por cada region de
%% ListaDeRegiones (la salida de dividir/4) y espera todos los
%% resultados. Como corren en paralelo, pueden terminar en cualquier
%% orden -- por eso cada uno vuelve etiquetado con su Ini.
%% procesar_paralelo([[Ini,Submatriz],...], Radio, ArchivoKernel, Ancho,
%%   Filtro) -> [{Ini,Filas}, ...]
%% ---------------------------------------------------------------------
procesar_paralelo(ListaDeRegiones, Radio, ArchivoKernel, Ancho, Filtro) ->
    Padre = self(),
    lists:foreach(
        fun([Ini, Submatriz]) ->
            spawn(fun() -> trabajador(Padre, Ini, Radio, Submatriz, ArchivoKernel, Ancho, Filtro) end)
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



%% ---------------------------------------------------------------------
%% fila_pascal/1: fila N del triangulo de Pascal [C(N,0), ..., C(N,N)].
%% Cada coeficiente se saca del anterior: C(N,K+1) = C(N,K)*(N-K)/(K+1)
%% ---------------------------------------------------------------------
fila_pascal(N) -> fila_pascal(N, 0, 1).

fila_pascal(N, K, _Actual) when K > N -> [];
fila_pascal(N, K, Actual) ->
    Siguiente = Actual * (N - K) div (K + 1),
    [Actual | fila_pascal(N, K + 1, Siguiente)].

%% ---------------------------------------------------------------------
%% escalar_fila/2: multiplica cada elemento de Fila por Escalar.
%% ---------------------------------------------------------------------
escalar_fila(_Escalar, []) -> [];
escalar_fila(Escalar, [H | T]) -> [Escalar * H | escalar_fila(Escalar, T)].

%% ---------------------------------------------------------------------
%% producto_exterior/2: cada elemento de la primera lista genera una
%% fila de la matriz (esa fila completa escalada por el elemento).
%% ---------------------------------------------------------------------
producto_exterior([], _Fila) -> [];
producto_exterior([H | T], Fila) ->
    [escalar_fila(H, Fila) | producto_exterior(T, Fila)].

