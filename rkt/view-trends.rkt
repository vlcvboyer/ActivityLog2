#lang racket/base
;; view-trends.rkt -- trends graphs
;;
;; This file is part of ActivityLog2, an fitness activity tracker
;; Copyright (C) 2015 Alex Harsanyi (AlexHarsanyi@gmail.com)
;;
;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation, either version 3 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
;; more details.

(require
 racket/class
 racket/gui/base
 racket/match
 racket/list
 racket/runtime-path
 "utilities.rkt"
 "widgets.rkt"
 "snip-canvas.rkt"
 "icon-resources.rkt"
 "trends-chart.rkt"
 "trends-bw.rkt"
 "trends-vol.rkt"
 "trends-trivol.rkt"
 "trends-tiz.rkt"
 "trends-pmc.rkt"
 "trends-tt.rkt"
 "trends-bavg.rkt"
 "trends-hist.rkt"
 "trends-scatter.rkt")

(provide view-trends%)


;;......................................................... view-trends% ....

(define-runtime-path trends-bw-file "../img/trends/trends-bw.png")
(define-runtime-path trends-trivol-file "../img/trends/trends-trivol.png")
(define-runtime-path trends-pmc-file "../img/trends/trends-pmc.png")
(define-runtime-path trends-vol-file "../img/trends/trends-vol.png")
(define-runtime-path trends-tiz-file "../img/trends/trends-tiz.png")
(define-runtime-path trends-tt-file "../img/trends/trends-tt.png")
(define-runtime-path trends-bavg-file "../img/trends/trends-bavg.png")
(define-runtime-path trends-hist-file "../img/trends/trends-hist.png")
(define-runtime-path trends-scatter-file "../img/trends/trends-scatter.png")

;; A trends chart declaration.  Contains some description and a sample image,
;; plus the class to be instantiated for the actual trends chart.
(struct tdecl
  (name
   tag
   class
   sample-image
   description))

(define chart-types
  (list
   (tdecl
    "Body Weight" 'bw bw-trends-chart%
    trends-bw-file
    "Plot body weight over time")
   
   (tdecl
    "Traning Volume (multisport)" 'trivol trivol-trends-chart%
    trends-trivol-file
    "Show training volume (time, distance, or number of activities) over time for triathlon activities (swim, bike, run and strength)")
   
   (tdecl
    "Traning Volume" 'vol vol-trends-chart%
    trends-vol-file
    "Show training volume (time, distance, or number of activities) over time for an activity type"
    )
   
   (tdecl
    "Time in Zone" 'tiz tiz-trends-chart%
    trends-tiz-file
    "Show time spent in each heart rate zone for a selected activity type over time")
   
   (tdecl
    "Performance" 'pmc pmc-trends-chart%
    trends-pmc-file
    "Plot form, fitness and fatigue over time.")
   
   (tdecl
    "Training Times" 'tt tt-trends-chart%
    trends-tt-file
    "Plot the time of day over weekday when each activity occured.")
   
   (tdecl
    "Best Avg" 'bavg bavg-trends-chart%
    trends-bavg-file
    "Plot the best-average (mean maximal) for a data series from selected activities.  Can also esitmate Critical Power or Critical Velocity")
   
   (tdecl
    "Histogram" 'hist hist-trends-chart%
    trends-hist-file
    "Plot a histogram for the data series from selected activities."
    )

   (tdecl
    "Scatter Plot" 'scatter scatter-trends-chart%
    trends-scatter-file
    "Scatter Plot for two data series from selected activities."
    )
   ))

;; Keep the loaded preview images for the chart types in a cache, we don't
;; load them at start up, since they might never be needed, but once loaded we
;; want to keep them around.
(define icon-cache (make-hash))

(define (get-bitmap file)
      (define icon (hash-ref icon-cache file #f))
      (unless icon
        (set! icon (read-bitmap file))
        (hash-set! icon-cache file icon))
      icon)

(define new-trend-chart-dialog%
  (class al-edit-dialog%
    (super-new [title "New Chart"]
               [icon (reports-icon)]
               [save-button-name "Select"]
               [min-height 10])

    (define chart-choice #f)
    (define sample-image (get-bitmap (tdecl-sample-image (first chart-types))))
    (define description #f)

    (let ((p (send this get-client-pane)))
      (let ((p0 (make-horizontal-pane p #f)))
        (send p0 spacing 20)
        (let ((p1 (make-vertical-pane p0 #t)))
          (send p1 spacing 20)
          (set! chart-choice
                (new choice%
                     [parent p1] [label "Chart Type "]
                     [choices (map tdecl-name chart-types)]
                     [callback (lambda (c e) (on-chart-selected (send c get-selection)))]))
          (define c (new editor-canvas% [parent p1] [style '(no-hscroll)]))
          (set! description (new text%))
          (send c set-editor description)
          (send description set-tabs '(8) 8 #f)
          (send description auto-wrap #t))
        (set! sample-image (new message%
                              [label sample-image]
                              [parent p0]
                              [min-width 400] [min-height 214]
                              [stretchable-width #f] [stretchable-height #f]))))

    ;; Setup the description for the selected chart type.
    (define (setup-chart-description n)
      (define ci (list-ref chart-types n))
      (define text (tdecl-description ci))
      (send description lock #f)
      (send description begin-edit-sequence)
      (send description select-all)
      (send description clear)
      (send description insert (make-object string-snip% text))
      (send description set-modified #f)
      (send description end-edit-sequence)
      (send description lock #t))

    ;; Set the sample image and description text for the selected chart type.
    (define (on-chart-selected n)
      (define ci (list-ref chart-types n))
      (define image (get-bitmap (tdecl-sample-image ci)))
      (send sample-image set-label image)
      (setup-chart-description n))

    ;; Setup the first one, as `on-chart-selected` will not be invoked the
    ;; first time the dialog is shown.
    (setup-chart-description 0)

    (define/public (show-dialog parent)
      (if (send this do-edit parent)
          (list-ref chart-types (send chart-choice get-selection))
          #f))))

(define trend-chart-pane%
  (class panel%
    (init-field parent info-tag trend-chart)
    (super-new [parent parent] [style '(deleted)])

    (define first-activation? #t)
    (define graph-pb (new snip-canvas% [parent this]))

    (define/public (get-name)
      (send trend-chart get-name))

    (define/public (get-title)
      (send trend-chart get-title))

    (define/public (activate)
      (when first-activation?
        (refresh-chart)))
    
    (define/public (refresh-chart)
      (send trend-chart invalidate-data)
      (send trend-chart put-plot-snip graph-pb)
      (set! first-activation? #f))

    (define/public (interactive-setup parent)
      (if (send trend-chart interactive-setup parent)
          (begin
            (refresh-chart)
            #t)
          #f))

    (define/public (get-restore-data)
      (list info-tag (send trend-chart get-restore-data)))

    (define/public (export-image-to-file file)
      (send graph-pb export-image-to-file file))

    (define/public (export-data-to-file file formatted?)
      (send trend-chart export-data-to-file file formatted?))

    ))

(define view-trends%
  (class object%
    (init-field parent database)
    (super-new)

    (define tag 'activity-log:view-trends)

    (define pane 
      (new (class vertical-panel%
             (init)
             (super-new)
             (define/public (interactive-export-image)
               (on-interactive-export-image))
             (define/public (interactive-export-data formatted?)
               (on-interactive-export-data formatted?)))
           [parent parent]
           [alignment '(left center)]))

    (define title-field #f)
    (define move-left-button #f)
    (define move-right-button #f)

    (let ((sel-pane (new horizontal-pane% [parent pane] 
                         [spacing 20]
                         [border 0]
                         [stretchable-height #f]
                         [stretchable-width #t]
                         [alignment '(left center)])))

      (make-spacer sel-pane)
      (new message% [parent sel-pane] [label (reports-icon)])

      (let ([font (send the-font-list find-or-create-font 14 'default 'normal 'normal)])
        (set! title-field (new message% [parent sel-pane] [font font]
                               [label ""] [stretchable-width #t])))

      (set! move-left-button
            (new button% [parent sel-pane] [label "Move left"]
                 [callback (lambda (b e) (on-move-left))]))
      (set! move-right-button
            (new button% [parent sel-pane] [label "Move right"]
                 [callback (lambda (b e) (on-move-right))]))
      (make-spacer sel-pane 30)
      (new button% [parent sel-pane] [label "New..."]
           [callback (lambda (b e) (on-new-chart))])
      (new button% [parent sel-pane] [label "Delete..."]
           [callback (lambda (b e) (on-delete-chart))])
      (new button% [parent sel-pane] [label "Setup..."]
           [callback (lambda (b e) (on-setup-chart))])
      (make-spacer sel-pane))

    (define trend-charts '())

    (define trend-charts-panel
      (new tab-panel%
           [stretchable-height #t]
           [choices '()]
           [callback (lambda (p c)
                       (switch-tabs (send p get-selection)))]
           [parent pane]))

    (define (restore-previous-charts)
      (let ((data (get-pref tag (lambda () #f))))

        (define (find-tdecl tag)
          (let loop ((chart-types chart-types))
            (if (null? chart-types)
                #f
                (if (eq? tag (tdecl-tag (car chart-types)))
                    (car chart-types)
                    (loop (cdr chart-types))))))

        (define (make-trends-chart chart-tag restore-data)
          (define ci (find-tdecl chart-tag))
          (when ci
            (let ((pane (let ((tc (new (tdecl-class ci) [database database])))
                          (send tc restore-from restore-data)
                          (new trend-chart-pane%
                               [parent trend-charts-panel]
                               [info-tag (tdecl-tag ci)]
                               [trend-chart tc]))))
              (set! trend-charts (append trend-charts (list pane)))
              (send trend-charts-panel append (send pane get-name)))))
      
        (when (and data (> (length data) 0))
          (let ((first-chart (car data)))
            (match-define (list chart-tag restore-data) first-chart)
            (make-trends-chart chart-tag restore-data))
          (switch-tabs 0)
          (for ([chart-data (cdr data)])
            (match-define (list chart-tag restore-data) chart-data)
            (queue-callback
             (lambda ()
               (make-trends-chart chart-tag restore-data))
             #f)))))
          
    (define (on-new-chart)
      (let ((ct (send (new new-trend-chart-dialog%) show-dialog parent)))
        (when ct
          (let ((pane (let ((tc (new (tdecl-class ct) [database database])))
                        (new trend-chart-pane%
                             [parent trend-charts-panel]
                             [info-tag (tdecl-tag ct)]
                             [trend-chart tc]))))
            (when (send pane interactive-setup parent)
              (set! trend-charts (append trend-charts (list pane)))
              (send trend-charts-panel append (send pane get-name))
              (switch-tabs (- (length trend-charts) 1)))))))
    
    (define (on-delete-chart)
      (let ((n (send trend-charts-panel get-selection)))
        (when n
          (let ((c (list-ref trend-charts n)))
            (let ((mresult (message-box/custom
                            "Confirm delete"
                            (format "Really delete chart \"~a\"?" (send c get-name))
                            #f "Delete" "Cancel"
                            (send parent get-top-level-window)
                            '(caution default=3))))
              (when (equal? mresult 2)
                (send trend-charts-panel delete n)
                (if (eqv? n 0)
                    (set! trend-charts (cdr trend-charts)) ; deletin first item
                    (let-values (([head tail] (split-at trend-charts n)))
                      (set! trend-charts (append head (cdr tail)))))
                (cond ((> (length trend-charts) n)
                       (switch-tabs n))
                      ((> (length trend-charts) 0)
                       (switch-tabs (- (length trend-charts) 1)))
                      (#t
                       (send trend-charts-panel change-children (lambda (old) (list)))))))))))
    
    (define (on-setup-chart)
      (let ((n (send trend-charts-panel get-selection)))
        (when n
          (let ((c (list-ref trend-charts n)))
            (send c interactive-setup parent)
            (let ((nname (send c get-name))
                  (ntitle (send c get-title)))
              (send trend-charts-panel set-item-label n nname)
              (send title-field set-label ntitle))))))

    (define (on-move-left)
      (define sel (send trend-charts-panel get-selection))
      (when (and sel (> sel 0))
        (let-values (((head tail) (split-at trend-charts (sub1 sel))))
          (set! trend-charts (append head (list (car (cdr tail))) (list (car tail)) (cdr (cdr tail)))))
        (after-move (sub1 sel))))
        
    (define (on-move-right)
      (define sel (send trend-charts-panel get-selection))
      (when (and sel (< sel (sub1 (length trend-charts))))
        (let-values (((head tail) (split-at trend-charts sel)))
          (set! trend-charts (append head (list (car (cdr tail))) (list (car tail)) (cdr (cdr tail)))))
        (after-move (add1 sel))))

    (define (after-move new-sel)
      (for (((chart index) (in-indexed (in-list trend-charts))))
        (send trend-charts-panel set-item-label index (send chart get-name)))
      (send trend-charts-panel set-selection new-sel)
      (send move-left-button enable (not (zero? new-sel)))
      (send move-right-button enable (< new-sel (sub1 (length trend-charts)))))
    
    (define (switch-tabs n)
      (send trend-charts-panel set-selection n)
      (let ((chart (list-ref trend-charts n)))
        (send trend-charts-panel change-children
              (lambda (old) (list chart)))
        (queue-callback  ; activate it later, so that the canvas gets its size
         (lambda () (send chart activate))
         #f)
        (send title-field set-label (send chart get-title)))
      (send move-left-button enable (not (zero? n)))
      (send move-right-button enable (< n (sub1 (length trend-charts)))))

    (define (with-exn-handling name thunk)
      (with-handlers
        (((lambda (e) #t)
          (lambda (e)
            ;; NOTE: 'print-error-trace' will only print a stack trace if the
            ;; error trace library is used.  To use it, remove all .zo files
            ;; and run "racket -l errortrace -t run.rkt"
            (let ((message (if (exn? e) (exn-message e) e)))
              (dbglog-exception name e)
              (message-box name message
                           (send parent get-top-level-window)
                           '(ok stop))))))
        (thunk)))
    
    (define (on-interactive-export-image)
      (with-exn-handling
        "on-interactive-export-image"
        (lambda ()
          (let ((n (send trend-charts-panel get-selection)))
            (when n
              (let* ((c (list-ref trend-charts n))
                     (file (put-file "Select file to export to" #f #f
                                     (format "~a.png" (send c get-name))
                                     "png" '()
                                     '(("PNG Files" "*.png") ("Any" "*.*")))))
                (when file
                  (send c export-image-to-file file))))))))
        
    (define (on-interactive-export-data formatted?)
      (with-exn-handling
        "on-interactive-export-data"
        (lambda ()
          (let ((n (send trend-charts-panel get-selection)))
            (when n
              (let* ((c (list-ref trend-charts n))
                     (file (put-file "Select file to export to" #f #f
                                     (format "~a.csv" (send c get-name))
                                     "csv" '()
                                     '(("CSV Files" "*.csv") ("Any" "*.*")))))
                (when file
                  (send c export-data-to-file file formatted?))))))))
        
    (define first-activation #t)

    (define/public (activated)
      (when first-activation
        (restore-previous-charts)
        (set! first-activation #f)))

    (define/public (refresh)
      (let ((n (send trend-charts-panel get-selection)))
        (when n
          (let ((c (list-ref trend-charts n)))
            (send c refresh-chart)))))

    (define/public (save-visual-layout)
      ;; Charts for this view are loaded on first activation (see `activate'),
      ;; if the view was not activated, don't save anything, otherwise we will
      ;; erase all our charts.
      (unless first-activation
        (let ((data (for/list ([tc trend-charts]) (send tc get-restore-data))))
          (put-pref tag data))))
    
    ))
