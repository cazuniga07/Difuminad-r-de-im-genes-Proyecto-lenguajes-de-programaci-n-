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

(define extender(lambda(matriz k)
  (map(lambda(fila)(append(make-list(quotient(- k 1) 2)(car fila)) fila(make-list(quotient(- k 1) 2)(car(reverse fila)))))matriz)))


(define despiche(lambda(matriz kernel k)
   (transpuesta(matriz-pichuda (proceso(extender(cosita matriz)k)kernel k)
                   (proceso(extender(cosita(map(lambda(fila)(map(lambda(pix) (cdr pix)) fila))matriz))k) kernel k)
                   (proceso(extender(cosita(map(lambda(fila)(map(lambda(pix)(cdr(cdr pix)))fila))matriz))k)kernel k)))));une las 3 matrices ya procesadas matriz de R, matriz de G y matriz de B


(define proceso-fila(lambda(matriz kernel k)
  (cond
    ((<(length (car matriz))k) '())
     (else(cons(pixeles(map(lambda(fila)(take fila k))(take matriz k))kernel)
               (proceso-fila(map(lambda(fila)(cdr fila)) matriz)kernel k))))))



(define proceso(lambda(matriz kernel k)
  (cond
    ((< (length matriz) k) '())
    (else(cons(proceso-fila matriz kernel k)(proceso(cdr matriz ) kernel k))))))


(define leer-archivo (lambda (nombre)
    (call-with-input-file nombre
      (lambda (archivo)
        (port->lines archivo)))))

(define tonumbers(lambda(linea)
   (map string->number(string-split linea))))

(define agrupar(lambda(lista)
  (cond
    ((null? lista)'())
    (else(cons(list (car lista) (cadr lista)(caddr lista))(agrupar(cdddr lista)))))))



(define entrada-region (lambda(nombre)
    (cons
     (string->number (car (leer-archivo nombre)))
     (map (lambda(linea)
            (agrupar (tonumbers linea)))
          (cdr (leer-archivo nombre))))))

(define entrada-kernel (lambda(nombre)
    (map (lambda(linea)
           (tonumbers linea))
         (leer-archivo nombre))))

(define final(lambda(matriz)
  (string-join(map number->string(apply append(map(lambda(fila)(apply append fila))matriz)))" ")))

(define recortar-halo
  (lambda(filas radio)
    (take
     (drop filas radio)
     (- (length filas) (* 2 radio)))))

(define main
  (lambda(archivo-region archivo-kernel archivo-salida filtro)
    (call-with-output-file archivo-salida
      (lambda(salida)
        (cond
          ((string=? filtro "gaussian")
           (display
            (final
             (despiche
              (cdr (entrada-region archivo-region))
              (entrada-kernel archivo-kernel)
              (+ (* 2 (car (entrada-region archivo-region))) 1)))
            salida))

          ((string=? filtro "invertir")
           (display
            (string-join
             (map number->string
                  (invertir-colores
                   (recortar-halo
                    (cdr (entrada-region archivo-region))
                    (car (entrada-region archivo-region)))))
             " ")
            salida))))
      #:exists 'replace)))
(define aplanar(lambda(matriz)
  (apply append(map(lambda(fila)(apply append fila))matriz))))

(define invertir-colores(lambda(matriz)
  (invertir(aplanar matriz))))

(define invertir(lambda(lista)
  (cond
    ((null? lista) '())
    (else(cons (- 255 (car lista)) (invertir (cdr lista)))))))

(command-line
 #:args (archivo-region archivo-kernel archivo-salida filtro)
 (main archivo-region archivo-kernel archivo-salida filtro))
