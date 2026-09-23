#lang racket
(define divisor (lambda(matriz)
  (apply + (map (lambda(fila)(apply + fila)) matriz)))); nos dice el divisor del kernel papu :v


(define transpuesta(lambda(matriz)
  (cond
    ((null? (car matriz)) '())
    (else (cons(map(lambda(fila)(car fila))matriz)(transpuesta(map (lambda(fila)(cdr fila)) matriz))))))) ;pos saca la transpuesta que mas quiere :)

(define pixeles(lambda (matriz kernel)
  (quotient(apply +(map (lambda(filaM filaK)(apply +(map(lambda (m k)(* m k)) filaM filaK)))matriz kernel))(divisor kernel)))); hace el proceso gaussiano por color todo lindo

(define cosita(lambda(matriz)
    (map(lambda(fila)(map(lambda(pix)(car pix)) fila))matriz))) ;Crea una matriz con el primer color de los pixeles, primero el rojo, despues se le pasa la matriz sin el R entonces agarra G y asi :)

(define matriz-pichuda(lambda(matriz1 matriz2 matriz3)
  (cond
    ((null? (car matriz1))'())
    (else(cons(map(lambda(fila1 fila2 fila3)(list (car fila1)(car fila2)(car fila3)))matriz1 matriz2 matriz3)
       (matriz-pichuda (map(lambda(fila1)(cdr fila1))matriz1) (map(lambda(fila2)(cdr fila2))matriz2) (map(lambda(fila3)(cdr fila3))matriz3))))))); Agarra las 3 matrices que separamos antes y las une de nuevo

(define despiche(lambda(matriz kernel k)
   (transpuesta(matriz-pichuda (proceso(cosita matriz)kernel k)
                   (proceso(cosita(map(lambda(fila)(map(lambda(pix) (cdr pix)) fila))matriz)) kernel k)
                   (proceso(cosita(map(lambda(fila)(map(lambda(pix)(cdr(cdr pix)))fila))matriz))kernel k)))));esto hay que arreglarlo,une las 3 matrices ya procesadas matriz de R, matriz de G y matriz de B


(define proceso-fila(lambda(matriz kernel k)
  (cond
    ((<(length (car matriz))k) '())
     (else(cons(pixeles(map(lambda(fila)(take fila k))(take matriz k))kernel)
               (proceso-fila(map(lambda(fila)(cdr fila)) matriz)kernel k))))))


                                   
(define proceso(lambda(matriz kernel k)
  (cond
    ((< (length matriz) k) '())
    (else(cons(proceso-fila matriz kernel k)(proceso(cdr matriz ) kernel k))))))


(define leer-archivo
  (lambda (nombre)
    (call-with-input-file nombre
      (lambda (archivo)
        (port->lines archivo)))))

(define tonumbers(lambda(linea)
   (map string->number(string-split linea))))

(define agrupar(lambda(lista)
  (cond
    ((null? lista)'())
    (else(cons(list (car lista) (cadr lista)(caddr lista))(agrupar(cdddr lista)))))))



(define entrada-region
  (lambda(nombre)
    (cons
     (string->number (car (leer-archivo nombre)))
     (map (lambda(linea)
            (agrupar (tonumbers linea)))
          (cdr (leer-archivo nombre))))))

(define entrada-kernel
  (lambda(nombre)
    (map (lambda(linea)
           (tonumbers linea))
         (leer-archivo nombre))))

(define final(lambda(matriz)
  (string-join(map number->string(apply append(map(lambda(fila)(apply append fila))matriz)))" ")))

(define main
  (lambda(archivo-region archivo-kernel)
    (display
     (final
      (despiche
       (cdr (entrada-region archivo-region))
       (entrada-kernel archivo-kernel)
       (car (entrada-region archivo-region)))))))

(command-line
 #:args (archivo-region archivo-kernel)
 (main archivo-region archivo-kernel))