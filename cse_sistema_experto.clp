;;;; ====================================================================
;;;; SISTEMA EXPERTO BASADO EN REGLAS PARA LA DETERMINACION AUDITABLE
;;;; DE LA CLASIFICACION SOCIOECONOMICA (CSE)  -  UNMSM / FISI
;;;; Curso: Sistemas Inteligentes 2026-2
;;;;
;;;; Metodo de inferencia: encadenamiento hacia adelante (forward chaining)
;;;; Fuentes: Formato S100 (R.M. N 069-2024-MIDIS), INEI - ENAHO 2025
;;;;          (Modulos 100, 200 y Sumaria), INEI - Pobreza Multidimensional.
;;;;
;;;; BASE DE CONOCIMIENTO: 30 REGLAS (defrule) en 3 capas.
;;;; La prioridad de disparo se controla con salience:
;;;;   CAPA 1  derivacion de hechos (salience 100) ......... R01 - R08
;;;;   CAPA 2  privaciones INEI     (salience 50 y 45) ..... R09 - R20
;;;;   CAPA 3  dictamen, vulnerabilidad y alertas
;;;;           (salience 40 a 10) .......................... R21 - R30
;;;; MODULO DE EXPLICACION: funcion (informe) que imprime el dictamen
;;;; y la traza de reglas disparadas.
;;;;
;;;; USO:   (load "cse_sistema_experto.clp")
;;;;        (caso-1)  ...  (caso-5)      o bien      (correr-todos)
;;;; NOTA: el archivo no usa tildes a proposito, para evitar problemas
;;;;       de codificacion en la consola de CLIPS.
;;;; ====================================================================

;;; --------------------------------------------------------------------
;;; PLANTILLAS (base de hechos)
;;; --------------------------------------------------------------------

;;; Hecho de entrada: un hogar (campos del S100 / ENAHO 2025)
(deftemplate hogar
   (slot id (type SYMBOL))
   (slot clave (type STRING))               ; CONGLOME-VIVIENDA-HOGAR
   (slot area (type SYMBOL) (allowed-symbols urbano rural))
   (slot miembros (type INTEGER))           ; MIEPERHO (Sumaria)
   (slot menores15 (type INTEGER))          ; miembros con edad < 15   (Modulo 200)
   (slot mayores60 (type INTEGER))          ; miembros con edad >= 60  (Modulo 200)
   (slot activos (type INTEGER))            ; miembros de 15 a 59 anos (Modulo 200)
   (slot habitaciones (type INTEGER))       ; P104 (Modulo 100)
   (slot piso (type SYMBOL) (allowed-symbols tierra otro))                       ; P103
   (slot luz (type SYMBOL) (allowed-symbols exclusivo compartido sin-servicio))  ; P1121, P112A
   (slot agua (type SYMBOL) (allowed-symbols red otro))                          ; P110
   (slot saneamiento (type SYMBOL) (allowed-symbols adecuado inadecuado))        ; P111A
   (slot combustible (type SYMBOL) (allowed-symbols limpio solido))              ; P113x
   (slot internet (type SYMBOL) (allowed-symbols si no))                         ; P1144
   (slot gasto-pc (type NUMBER))            ; gasto per capita mensual (soles)
   (slot linpe (type NUMBER))               ; linea de pobreza extrema (LPE)
   (slot linea (type NUMBER)))              ; linea de pobreza total (LPT)

;;; Hechos derivados por las reglas (con la regla que los produjo)
(deftemplate hecho
   (slot hogar (type SYMBOL))
   (slot atributo (type SYMBOL))
   (slot valor)
   (slot regla (type SYMBOL)))

;;; Privaciones detectadas (Capa 2)
(deftemplate privacion
   (slot hogar (type SYMBOL))
   (slot nombre (type SYMBOL))
   (slot peso (type INTEGER))
   (slot base (type STRING))
   (slot regla (type SYMBOL)))

;;; --------------------------------------------------------------------
;;; CAPA 1: DERIVACION DE HECHOS  (salience 100)          R01 - R08
;;; --------------------------------------------------------------------

;;; Tramo de gasto (regla de decision monetaria del INEI)
(defrule R01-tramo-bajo-lpe
   "Gasto per capita menor a la linea de pobreza extrema"
   (declare (salience 100))
   (hogar (id ?h) (gasto-pc ?g) (linpe ?lpe))
   (test (< ?g ?lpe))
   =>
   (assert (hecho (hogar ?h) (atributo tramo) (valor bajo-lpe) (regla R01))))

(defrule R02-tramo-entre-lpe-lpt
   "Gasto per capita entre la LPE y la linea de pobreza total"
   (declare (salience 100))
   (hogar (id ?h) (gasto-pc ?g) (linpe ?lpe) (linea ?lt))
   (test (and (>= ?g ?lpe) (< ?g ?lt)))
   =>
   (assert (hecho (hogar ?h) (atributo tramo) (valor entre) (regla R02))))

(defrule R03-tramo-sobre-lpt
   "Gasto per capita igual o mayor a la linea de pobreza total"
   (declare (salience 100))
   (hogar (id ?h) (gasto-pc ?g) (linea ?lt))
   (test (>= ?g ?lt))
   =>
   (assert (hecho (hogar ?h) (atributo tramo) (valor sobre) (regla R03))))

;;; Tasa de dependencia = (menores de 15 + mayores de 60) / (miembros de 15 a 59)
;;; Baja: <= 0.5   Media: > 0.5 y <= 1.0   Alta: > 1.0   (supuesto del modelo)
(defrule R04-dependencia-alta
   "Dependientes superan a los miembros en edad activa (S100 num. 6)"
   (declare (salience 100))
   (hogar (id ?h) (menores15 ?m) (mayores60 ?a) (activos ?act))
   (test (> (+ ?m ?a) ?act))
   =>
   (assert (hecho (hogar ?h) (atributo dependencia) (valor alta) (regla R04))))

(defrule R05-dependencia-media
   "Dependientes entre la mitad y la totalidad de los miembros activos"
   (declare (salience 100))
   (hogar (id ?h) (menores15 ?m) (mayores60 ?a) (activos ?act))
   (test (and (<= (+ ?m ?a) ?act) (> (* 2 (+ ?m ?a)) ?act)))
   =>
   (assert (hecho (hogar ?h) (atributo dependencia) (valor media) (regla R05))))

(defrule R06-dependencia-baja
   "Dependientes no superan la mitad de los miembros activos"
   (declare (salience 100))
   (hogar (id ?h) (menores15 ?m) (mayores60 ?a) (activos ?act))
   (test (<= (* 2 (+ ?m ?a)) ?act))
   =>
   (assert (hecho (hogar ?h) (atributo dependencia) (valor baja) (regla R06))))

;;; Hacinamiento: mas de 3 personas por habitacion (INEI, Indicador 15)
(defrule R07-hacinamiento-si
   "Mas de 3 miembros por habitacion"
   (declare (salience 100))
   (hogar (id ?h) (miembros ?m) (habitaciones ?hab))
   (test (> ?m (* 3 ?hab)))
   =>
   (assert (hecho (hogar ?h) (atributo hacinamiento) (valor si) (regla R07))))

(defrule R08-hacinamiento-no
   "3 o menos miembros por habitacion"
   (declare (salience 100))
   (hogar (id ?h) (miembros ?m) (habitaciones ?hab))
   (test (<= ?m (* 3 ?hab)))
   =>
   (assert (hecho (hogar ?h) (atributo hacinamiento) (valor no) (regla R08))))

;;; --------------------------------------------------------------------
;;; CAPA 2: PRIVACIONES SEGUN INDICADORES DEL INEI          R09 - R20
;;; Los pesos son un supuesto academico del modelo (documentar en el informe)
;;; --------------------------------------------------------------------

;;; --- Privaciones directas (salience 50) ---

(defrule R09-habitabilidad-critica
   "Hacinamiento y piso de tierra a la vez"
   (declare (salience 50))
   (hogar (id ?h) (piso tierra))
   (hecho (hogar ?h) (atributo hacinamiento) (valor si))
   =>
   (assert (privacion (hogar ?h) (nombre habitabilidad-critica) (peso 3)
                      (base "INEI Priv. conjunta IX.3 Habitabilidad (hacinamiento y piso de tierra)")
                      (regla R09))))

(defrule R10-piso-de-tierra
   "Piso de tierra sin hacinamiento"
   (declare (salience 50))
   (hogar (id ?h) (piso tierra))
   (hecho (hogar ?h) (atributo hacinamiento) (valor no))
   =>
   (assert (privacion (hogar ?h) (nombre piso-tierra) (peso 1)
                      (base "INEI Indicador 16: piso predominantemente de tierra")
                      (regla R10))))

(defrule R11-hacinamiento
   "Hacinamiento sin piso de tierra"
   (declare (salience 50))
   (hogar (id ?h) (piso otro))
   (hecho (hogar ?h) (atributo hacinamiento) (valor si))
   =>
   (assert (privacion (hogar ?h) (nombre hacinamiento) (peso 1)
                      (base "INEI Indicador 15: vivienda con hacinamiento")
                      (regla R11))))

(defrule R12-sin-electricidad
   "El hogar declara no tener servicio electrico"
   (declare (salience 50))
   (hogar (id ?h) (luz sin-servicio))
   =>
   (assert (privacion (hogar ?h) (nombre sin-electricidad) (peso 3)
                      (base "S100 num. 9 / INEI Indicador 21: sin acceso a energia electrica")
                      (regla R12))))

(defrule R13-electricidad-compartida
   "Servicio electrico con medidor de uso colectivo"
   (declare (salience 50))
   (hogar (id ?h) (luz compartido))
   =>
   (assert (privacion (hogar ?h) (nombre electricidad-compartida) (peso 1)
                      (base "S100 num. 9.2 (uso compartido) / INEI Indicador 21: acceso inadecuado")
                      (regla R13))))

(defrule R14-dependencia-alta-privacion
   "Composicion del hogar con dependencia alta"
   (declare (salience 50))
   (hogar (id ?h))
   (hecho (hogar ?h) (atributo dependencia) (valor alta))
   =>
   (assert (privacion (hogar ?h) (nombre dependencia-alta) (peso 1)
                      (base "S100 num. 6: composicion del hogar (menores y adultos mayores)")
                      (regla R14))))

(defrule R15-sin-agua-red-publica
   "El agua del hogar no proviene de la red publica"
   (declare (salience 50))
   (hogar (id ?h) (agua otro))
   =>
   (assert (privacion (hogar ?h) (nombre sin-agua-red) (peso 1)
                      (base "INEI Indicador 18 (proxy: agua no proviene de red publica)")
                      (regla R15))))

(defrule R16-saneamiento-inadecuado
   "Servicio higienico en pozo ciego, rio, campo abierto u otro"
   (declare (salience 50))
   (hogar (id ?h) (saneamiento inadecuado))
   =>
   (assert (privacion (hogar ?h) (nombre saneamiento-inadecuado) (peso 1)
                      (base "INEI Indicador 19 (proxy: sin alcantarillado ni disposicion sanitaria adecuada)")
                      (regla R16))))

(defrule R17-combustible-solido
   "Cocina con lena, carbon o bosta"
   (declare (salience 50))
   (hogar (id ?h) (combustible solido))
   =>
   (assert (privacion (hogar ?h) (nombre combustible-solido) (peso 1)
                      (base "INEI Indicador 22: combustibles solidos contaminantes para cocinar")
                      (regla R17))))

(defrule R18-sin-internet
   "El hogar no tiene conexion a internet (fija o movil)"
   (declare (salience 50))
   (hogar (id ?h) (internet no))
   =>
   (assert (privacion (hogar ?h) (nombre sin-internet) (peso 1)
                      (base "INEI Indicador 29 (proxy: hogar sin conexion a internet)")
                      (regla R18))))

;;; --- Privaciones encadenadas: dependen de privaciones ya inferidas
;;;     (segundo nivel de encadenamiento, salience 45) ---

(defrule R19-menores-expuestos
   "Hogar con menores de 15 y privacion de agua o saneamiento"
   (declare (salience 45))
   (hogar (id ?h) (menores15 ?m))
   (test (> ?m 0))
   (or (privacion (hogar ?h) (nombre sin-agua-red))
       (privacion (hogar ?h) (nombre saneamiento-inadecuado)))
   =>
   (assert (privacion (hogar ?h) (nombre menores-expuestos) (peso 1)
                      (base "Menores de 15 anos expuestos a riesgo sanitario (INEI Indicadores 18 y 19)")
                      (regla R19))))

(defrule R20-adultos-mayores-expuestos
   "Hogar con mayores de 60 y privacion de electricidad o combustible limpio"
   (declare (salience 45))
   (hogar (id ?h) (mayores60 ?a))
   (test (> ?a 0))
   (or (privacion (hogar ?h) (nombre sin-electricidad))
       (privacion (hogar ?h) (nombre combustible-solido)))
   =>
   (assert (privacion (hogar ?h) (nombre adultos-mayores-expuestos) (peso 1)
                      (base "Adultos mayores (60+) expuestos a privacion energetica (INEI Indicadores 21 y 22)")
                      (regla R20))))

;;; --------------------------------------------------------------------
;;; CAPA 3: DICTAMEN, VULNERABILIDAD Y ALERTAS              R21 - R30
;;; --------------------------------------------------------------------

;;; Dictamen oficial (monetario): salience 40
(defrule R21-dictamen-pobreza-extrema
   "Tramo bajo la LPE => Pobreza Extrema"
   (declare (salience 40))
   (hecho (hogar ?h) (atributo tramo) (valor bajo-lpe))
   =>
   (assert (hecho (hogar ?h) (atributo dictamen) (valor pobreza-extrema) (regla R21))))

(defrule R22-dictamen-pobreza-no-extrema
   "Tramo entre la LPE y la LPT => Pobreza No Extrema"
   (declare (salience 40))
   (hecho (hogar ?h) (atributo tramo) (valor entre))
   =>
   (assert (hecho (hogar ?h) (atributo dictamen) (valor pobreza-no-extrema) (regla R22))))

(defrule R23-dictamen-no-pobre
   "Tramo sobre la LPT => No Pobre"
   (declare (salience 40))
   (hecho (hogar ?h) (atributo tramo) (valor sobre))
   =>
   (assert (hecho (hogar ?h) (atributo dictamen) (valor no-pobre) (regla R23))))

;;; Puntaje de privaciones: suma de pesos. Se ejecuta cuando ya no quedan
;;; reglas de la Capa 2 pendientes (salience 30 < 45).
(defrule R24-puntaje-privaciones
   "Suma los pesos de las privaciones detectadas"
   (declare (salience 30))
   (hogar (id ?h))
   (not (hecho (hogar ?h) (atributo puntaje)))
   =>
   (bind ?total 0)
   (do-for-all-facts ((?p privacion)) (eq ?p:hogar ?h)
      (bind ?total (+ ?total ?p:peso)))
   (assert (hecho (hogar ?h) (atributo puntaje) (valor ?total) (regla R24))))

;;; Nivel de vulnerabilidad multidimensional: Baja 0-2, Media 3-5, Alta >= 6
(defrule R25-vulnerabilidad-baja
   "Puntaje de 0 a 2"
   (declare (salience 20))
   (hecho (hogar ?h) (atributo puntaje) (valor ?p))
   (test (<= ?p 2))
   =>
   (assert (hecho (hogar ?h) (atributo vulnerabilidad) (valor baja) (regla R25))))

(defrule R26-vulnerabilidad-media
   "Puntaje de 3 a 5"
   (declare (salience 20))
   (hecho (hogar ?h) (atributo puntaje) (valor ?p))
   (test (and (>= ?p 3) (<= ?p 5)))
   =>
   (assert (hecho (hogar ?h) (atributo vulnerabilidad) (valor media) (regla R26))))

(defrule R27-vulnerabilidad-alta
   "Puntaje de 6 o mas"
   (declare (salience 20))
   (hecho (hogar ?h) (atributo puntaje) (valor ?p))
   (test (>= ?p 6))
   =>
   (assert (hecho (hogar ?h) (atributo vulnerabilidad) (valor alta) (regla R27))))

;;; Alertas de gestion (combinan dictamen monetario y vulnerabilidad)
(defrule R28-alerta-atencion-prioritaria
   "Pobreza extrema con vulnerabilidad alta"
   (declare (salience 10))
   (hecho (hogar ?h) (atributo dictamen) (valor pobreza-extrema))
   (hecho (hogar ?h) (atributo vulnerabilidad) (valor alta))
   =>
   (assert (hecho (hogar ?h) (atributo alerta) (valor atencion-prioritaria) (regla R28))))

(defrule R29-alerta-seguimiento-recomendado
   "Pobreza no extrema con vulnerabilidad alta"
   (declare (salience 10))
   (hecho (hogar ?h) (atributo dictamen) (valor pobreza-no-extrema))
   (hecho (hogar ?h) (atributo vulnerabilidad) (valor alta))
   =>
   (assert (hecho (hogar ?h) (atributo alerta) (valor seguimiento-recomendado) (regla R29))))

(defrule R30-alerta-revision-recomendada
   "No pobre monetario con vulnerabilidad alta: posible exclusion"
   (declare (salience 10))
   (hecho (hogar ?h) (atributo dictamen) (valor no-pobre))
   (hecho (hogar ?h) (atributo vulnerabilidad) (valor alta))
   =>
   (assert (hecho (hogar ?h) (atributo alerta) (valor revision-recomendada) (regla R30))))

;;; --------------------------------------------------------------------
;;; MODULO DE EXPLICACION (funciones): informe auditable con la traza
;;; --------------------------------------------------------------------

;;; Devuelve el valor de un atributo derivado de un hogar (o "ninguna")
(deffunction valor-de (?h ?atr)
   (bind ?l (find-fact ((?f hecho)) (and (eq ?f:hogar ?h) (eq ?f:atributo ?atr))))
   (if (> (length$ ?l) 0)
      then (return (fact-slot-value (nth$ 1 ?l) valor))
      else (return ninguna)))

(deffunction informe (?id)
   (bind ?lh (find-fact ((?hh hogar)) (eq ?hh:id ?id)))
   (bind ?x (nth$ 1 ?lh))
   (printout t crlf "==============================================================" crlf)
   (printout t " INFORME AUDITABLE - HOGAR " ?id " (ENAHO 2025: " (fact-slot-value ?x clave) ")" crlf)
   (printout t "==============================================================" crlf)
   (printout t " Area: " (fact-slot-value ?x area) "   Miembros: " (fact-slot-value ?x miembros) crlf)
   (printout t " Gasto per capita mensual: S/ " (format nil "%.2f" (fact-slot-value ?x gasto-pc))
               "   (LPE: " (format nil "%.2f" (fact-slot-value ?x linpe))
               " | LPT: " (format nil "%.2f" (fact-slot-value ?x linea)) ")" crlf)
   (printout t " DICTAMEN (monetario) ........: " (valor-de ?id dictamen) crlf)
   (printout t " VULNERABILIDAD MULTIDIMENS. .: " (valor-de ?id vulnerabilidad)
               " (puntaje " (valor-de ?id puntaje) ")" crlf)
   (printout t " ALERTA ......................: " (valor-de ?id alerta) crlf)
   (printout t crlf " --- Traza de reglas disparadas ---" crlf)
   (do-for-all-facts ((?f hecho)) (eq ?f:hogar ?id)
      (printout t "  [" ?f:regla "] " ?f:atributo " = " ?f:valor crlf))
   (do-for-all-facts ((?q privacion)) (eq ?q:hogar ?id)
      (printout t "  [" ?q:regla "] privacion " ?q:nombre " (peso " ?q:peso ") - " ?q:base crlf))
   (printout t "==============================================================" crlf)
   (return TRUE))

;;; --------------------------------------------------------------------
;;; FUNCION DE EVALUACION Y LOS 5 CASOS (hogares reales, ENAHO 2025)
;;; Argumentos: id clave area miembros menores15 mayores60 activos
;;;             habitaciones piso luz agua saneamiento combustible internet
;;;             gasto-pc linpe linea
;;; --------------------------------------------------------------------
(deffunction evaluar (?id ?clave ?area ?miembros ?m15 ?m60 ?activos ?hab ?piso ?luz ?agua ?san ?comb ?inet ?gasto ?linpe ?linea)
   (reset)
   (assert (hogar (id ?id) (clave ?clave) (area ?area) (miembros ?miembros)
                  (menores15 ?m15) (mayores60 ?m60) (activos ?activos)
                  (habitaciones ?hab) (piso ?piso) (luz ?luz)
                  (agua ?agua) (saneamiento ?san) (combustible ?comb) (internet ?inet)
                  (gasto-pc ?gasto) (linpe ?linpe) (linea ?linea)))
   (run)
   (informe ?id)
   (return TRUE))

;;; Caso 1: rural, sin luz, hacinamiento y piso de tierra    (oficial: Pobreza Extrema)
(deffunction caso-1 () (evaluar H1 "15280-29-11" rural 5 3 0 2 1 tierra sin-servicio red inadecuado solido si 210.16 222.11 342.91))
;;; Caso 2: urbano de selva, sin luz, saneamiento inadecuado (oficial: Pobreza No Extrema)
(deffunction caso-2 () (evaluar H2 "20278-31-11" urbano 6 2 0 4 4 otro sin-servicio red inadecuado solido si 329.61 252.83 428.60))
;;; Caso 3: Lima, sin privaciones                            (oficial: No Pobre)
(deffunction caso-3 () (evaluar H3 "17800-78-11" urbano 4 0 2 2 5 otro exclusivo red adecuado limpio si 1220.26 307.24 568.01))
;;; Caso 4: rural, hacinado con piso de tierra, gasto alto   (oficial: No Pobre)
(deffunction caso-4 () (evaluar H4 "19413-537-11" rural 5 3 0 2 1 tierra exclusivo red inadecuado limpio si 668.36 215.29 373.46))
;;; Caso 5: gasto bajo pero casi sin privaciones             (oficial: Pobreza Extrema)
(deffunction caso-5 () (evaluar H5 "19681-18-11" urbano 5 2 0 3 3 tierra exclusivo red adecuado limpio si 246.24 252.83 412.11))

(deffunction correr-todos ()
   (caso-1) (caso-2) (caso-3) (caso-4) (caso-5)
   (return TRUE))
