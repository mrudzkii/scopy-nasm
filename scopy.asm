section .rodata                             ; Dla zwiększenia czytelności przechowuję tu kody, flagi i tryby funkcji systemowych.
    o_creat         equ 66
    rwrr            equ 420
    sys_write       equ 1
    sys_open        equ 2
    sys_close       equ 3
    sys_exit        equ 60
    O_WRONLY	    equ 00000001
    O_CREAT		    equ 00000100
    O_EXCL		    equ 00000200

section .data
    buffer_size     equ 4096                ; Rozmiar buforu - w testach był to najlepszy rozmiar, oprócz tego jest to rozmiar jednej
                                            ; ramki pamięci, stąd taki wybór rozmiaru.
    in_file_handle  dq 0                    ; Deskryptor pliku do odczytu.
    out_file_handle dq 0                    ; Deskrytptor pliku do zapisu.
    exit_code       db 1                    ; Domyślną wartość kodu wyniku ustawiam na 1, żeby przy każdym błędzie być 
                                            ; w stanie wyjść z programu z poprawnym kodem. Dopiero kiedy program wykona się
                                            ; poprawnie ustawię kod na 0.

section .bss
    read_buffer     resb buffer_size        ; Bufor do odczytu.
    write_buffer    resb buffer_size        ; Bufor do zapisu.
    number resb 2                           ; Pomocnicza zmienna do zapisu.

section .text
global _start  

_start: 
    ; Kolejne argumenty programu:
    ; rsp: liczba argumentów
    ; rsp + 8: nazwa programu
    ; rsp + 16: nazwa pliku do odczytu
    ; rsp + 24: nazwa pliku do zapisu
                                            ; Sprawdzenie, czy program ma dokładnie 2 argumenty.
    cmp     qword [rsp], 3                  ; Pierwszy argument to nazwa programu, stąd porównanie do 3.
    jne     .exit

.open_first_file:
    mov     rdi, [rsp + 16]                 ; Wskaźnik na nazwę pliku do otworzenia.
    xor     rsi, rsi                        ; W rsi przekazuję flagę, wartość 0 otwiera plik w trybie tylko do odczytu.
    mov     rax, sys_open
    syscall                                                                            
    test    rax, rax                        ; Jeśli funkcja sys_open wykona się poprawnie, to w rejestrze rax będzie
    js      .exit                           ; nieujemny deskryptor pliku, wynik ujemny oznacza błąd - kończę program.
    mov     [in_file_handle], rax           ; Zapisuję deskryptor do poźniejszego użycia.

.open_second_file:
    mov     rdi, [rsp + 24]                 ; Wskaźnik na nazwę pliku do otworzenia.
    mov     rsi, O_WRONLY | O_CREAT | O_EXCL; Flagi tworzące plik (jeśli nie istnieje) i otwierające go.
    mov     rdx, rwrr                       ; Ustawiam uprawnienia tworzonego pliku na -rw-r--r--.
    mov     rax, sys_open
    syscall
    test    rax, rax                        ; Ujemny wynik oznacza błąd.
    js      .close_in_file                  ; Przechodzę wówczas do zamknięcia otwartego wcześniej pliku wejściowego i kończę program.
    mov     [out_file_handle], rax          ; Dodatni wynik to deskryptor pliku - zapamiętuję go.

    xor     r10, r10                        ; r10 to licznik długości spójnego ciągu bez 's' lub 'S'.

; Ogólny koncept:
; Pętla buffer_loop służy do wczytywania do buforu kolejnych porcji danych. Pętla loop_over_buffer
; przechodzi po kolejnych bajtach buforu i zgodnie ze specyfikacją przepisuje je do buforu zapisu. 
; Po przejrzeniu całego buforu wejściowego zapisuję do pliku bufor wyjściowy.

.buffer_loop:                               ; Odczyt kolejnego buforu danych.
    xor     r9, r9                          ; r9 to indeks ostatniego elementu buforu zapisu.
    xor     rax, rax                        ; Funkcja sys_read ma kod 0, więc zeruję rax.
    mov     rdi, [in_file_handle]           ; W rdi przekazuję deskryptor pliku oczytu.
    mov     rsi, read_buffer                ; W rsi przekazuję miejsce, do którego dane mają zostać zapisane (bufor zapisu).
    mov     rdx, buffer_size                ; W rdx przekazuję ile maksymalnie bajtów chcę odczytać.
    syscall 
    test    rax, rax                        ; Sprawdzam wynik funkcji.
    jz      .end_loop                       ; Jeśli jest równy 0 to znaczy, że plik się skończył.
    js      .close_both_files               ; Jeśli jest ujemny to znaczy, że wystąpił błąd.
    mov     rcx, rax                        ; Wynikiem funkcji jest liczba wczytanych znaków, przechowuję ją, żeby dokładnie
                                            ; tyle znaków przejrzeć.
    xor     r8, r8                          ; Iterator buforu.

.loop_over_buffer:                          ;  Pętla do przechodzenia po wszystkich znakach obecnego buforu. 
    cmp     r8, rcx                         ; Jeśli skończył się bufor odczytu, to zapisuję bufor zapisu do pliku.
    je      .write_to_file  
    cmp     byte [read_buffer + r8], 's'    ; Jeśli trafiam na znak 's' lub 'S', to przechodzę do zapisu go do buforu.
    je      .write_to_bufor
    cmp     byte [read_buffer + r8], 'S'
    je      .write_to_bufor
    inc     r10                             ; W przeciwnym razie zwiększam licznik długości ciągu bez 's' ani 'S'.
    inc     r8                              ; Zwiększam również iterator buforu, żeby przejść do kolejnego znaku.
    jmp     .loop_over_buffer    

.write_to_bufor:                            ; Zapis danych na koniec buforu zapisu.
    test    r10, r10                        ; Jeśli licznik długości ciągu bez 's' ani 'S' jest różny od 0,
    jz      .only_s                         ; to wpisuję go do buforu zapisu.
    mov     word [write_buffer + r9], r10w  ; Najmłodsze 16 bitów rejestru r10 to szukana liczba mod 2^16.
    add     r9, 2                           ; Indeks ostaniego elementu buforu zwiększył się o 2 bajty (16 bitów).

.only_s:                                    ; Zapis do buforu litery 's' lub 'S'.
    mov     r10b, byte [read_buffer + r8]   ; Pomocniczo przechowuję literę do zapisu.
    mov     byte [write_buffer + r9], r10b  ; Zapisuję ją do buforu zapisu.
    xor     r10, r10                        ; Zeruję r10, który znowu będzie służył do liczenia dłg. ciągu bez 's' ani 'S'.
    inc     r8                              ; Zwiększam iterator buforu odczytu.
    inc     r9                              ; Oraz buforu zapisu (indeks ostatniego znaku zwiększył się o bajt).
    jmp     .loop_over_buffer               ; Przechodzę do kolejnego znaku z buforu odczytu.

.write_to_file:                             ; Zapis obecnego buforu do pliku.
    xor     r8, r8                          ; r8 będzie mi służył jako licznik dotychczas dopisanych danych.
    mov     rdi, [out_file_handle]          ; W rdi przekazuję deskryptor pliku zapisu.
    mov     rsi, write_buffer               ; Źródło zapisu - bufor.
.write_loop:                                ; * (dokładne wyjaśnienie na dole pliku).
    mov     rax, sys_write                  
    mov     rdx, r9                         ; W rdx przekazuję liczbę bajtów do wpisania - jest to wielkość buforu zapisu,
    sub     rdx, r8                         ; pomniejszona o liczbę dotychczas zapisanych bajtów.
    syscall 
    add     r8, rax                         ; Aktualizuję licznik dotychczas wpisanych do pliku bajtów.
    add     rsi, rax                        ; Oraz przesuwam wskaźnik na bufor o liczbę bajtów wpisanych w tej iteracji.
    cmp     r8, r9                          ; Jeśli wpisano już wszystkie dane, które chciałem, to kończę zapis.
    je      .buffer_loop                    ; Przechodzę do wczytania kolejnego buforu
    test    rax, rax
    js      .close_both_files               ; Wynik ujemny oznacza błąd zapisu, zamykam pliki i kończę błędem 
    jmp     .write_loop                     ; Jeśli nie wpisano wszystkich danych, ale nie nastąpił też błąd,
                                            ; to przechodzę do próby zapisania pozostałych danych.

.end_loop:
    mov     byte [exit_code], 0             ; Jeżeli program doszedł do tego momentu, to znaczy, że nie było błędu po drodze,
                                            ; więc póki co chcę mieć kod 0 (jeśli r10 == 0, to jedyne miejsce, gdzie może
                                            ; jeszcze wystąpić błąd, to przy zamykaniu plików).
        
    test    r10, r10                        ; Ten fragment sprawia, żeby w sytuacji, w której na ostatnim miejscu jest
                                            ; znak inny niż 's' lub 'S', długość takiego ciągu została zapisana do pliku.
    jz      .close_both_files               ; r10 == 0 oznacza, że na końcu było 's' lub 'S'.
    mov     byte [exit_code], 1             ; Ustawiam kod wyjścia na 1 w razie, gdyby nie udało się zapisać 
                                            ; długości ciągu do pliku.
    mov     word [number], r10w             ; Pomocniczo przechowuję długość tego ciągu.
    mov     rdx, 2                          ; Liczba ta jest 16-bitowa, więc zapiszę do pliku 2 bajty.
    mov     rsi, number                     ; W rsi przechowuję liczbę do zapisu.
    mov     rdi, [out_file_handle]          ; W rdi deskryptor pliku do zapisu.
    mov     rax, sys_write
    syscall
    test    rax, rax
    js      .close_both_files               ; Wynik ujemny oznacza błąd zapisu, zamykam pliki i kończę błędem.
    cmp     rax, 2                          ; *, mogła się zdarzyć sytuacja, że zapisano jedynie 1 z 2 bajtów, które chciałem.
    je      .succes
    mov     rdx, 1                          ; Ponawiam wtedy próbę zapisu ostatniego bajtu.
    inc     rsi                             ; Zwiększam wskaźnik buforu o 1.
    mov     rax, sys_write
    syscall
    test    rax, rax
    js      .close_both_files               ; W przypadku błędu kończę program z kodem 1.
.succes:
    mov     byte [exit_code], 0             ; W przeciwynym razie program zakończył się pomyślnie i zwróci błąd jedynie,
                                            ; jeśli zamykanie któregoś pliku się nie powiedzie.

.close_both_files:                          ; Zamykam obydwa pliki.
    mov     r9, [out_file_handle]           ; Najpierw plik wyjściowy.
    mov     rax, sys_close
    mov     rdi, r9                         ; W rdi przekazuję deskryptor pliku wyjściowego.
    syscall
    test    rax, rax
    jns     .close_in_file                  ; Wynik nieujemny oznacza brak błędu, więc kontynuuje zamykanie plików z kodem wyjścia 0.
    mov     byte [exit_code], 1             ; W p.p. nastąpił błąd, zamykam więc drugi plik, ale już z kodem wyjścia 1.

.close_in_file:                             ; Zamykam drugi plik.
    mov     r8, [in_file_handle]            ; Pomocniczo przenoszę deskryptor do r8.
    mov     rax, sys_close
    mov     rdi, r8                         ; Przenoszę deskryptor do argumentu funkcji sys_close.
    syscall
    test    rax, rax
    jns     .exit                           ; Wynik nieujemny to brak błędu - wychodzę z dotychczasowym kodem wyjścia.
    mov     byte [exit_code], 1             ; Wynik ujemny oznacza błąd, więc ustawiam kod wyjścia na 1.

.exit:
    mov     rax, sys_exit
    mov     rdi, [exit_code]                ; Funkcja sys_exit w rejestrze rdi przyjmuje kod wyjścia.
    syscall 


; *Zgodnie z dokumentacją funkcja sys_write nie musi zapisać od razu całego buforu do pliku i nie jest to błędem funkcji.
; Jeśli więc sys_write zapisze do pliku pewną dodatnią, ale mniejszą niż chciałem, liczbę bajtów (zwracaną w rax), to muszę
; powtarzać wykonywanie funkcji systemowej aż do wpisania wszystkich danych do pliku.
