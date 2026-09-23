#lang racket

;; Stub de prueba para validar el protocolo con Erlang (2 archivos de
;; entrada + 1 de salida). TODAVIA NO aplica el filtro real -- solo
;; recorta el halo de filas (identidad), para probar que el mecanismo
;; de puertos y archivos funciona de punta a punta.
;; TODO (parte de Scheme): reemplazar por el filtro real usando
;; despiche/proceso/etc.

(define (leer-numeros linea)
  (map string->number (string-split linea " ")))

(define (leer-region archivo)
  (with-input-from-file archivo
    (lambda ()
      (define radio (string->number (read-line)))
      (define filas
        (let loop ()
          (define linea (read-line))
          (if (eof-object? linea)
              '()
              (cons (leer-numeros linea) (loop)))))
      (list radio filas))))

(define (escribir-salida archivo filas)
  (with-output-to-file archivo #:exists 'replace
    (lambda ()
      (for ([fila filas])
        (displayln (string-join (map number->string fila) " "))))))

;; Placeholder: recorta 'radio' filas de arriba y de abajo (identidad).
(define (recortar-halo filas radio)
  (define n (length filas))
  (take (drop filas radio) (- n (* 2 radio))))

(define (main)
  (define args (current-command-line-arguments))
  (define archivo-region (vector-ref args 0))
  (define archivo-salida (vector-ref args 2))
  (define entrada (leer-region archivo-region))
  (define radio (first entrada))
  (define filas (second entrada))
  ;; TODO: reemplazar esta linea por el filtro real (despiche filas kernel).
  (define resultado (recortar-halo filas radio))
  (escribir-salida archivo-salida resultado))

(main)
