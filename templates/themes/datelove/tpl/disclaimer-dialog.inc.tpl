{* DeseoCerca 18+ entry gate. Terms and privacy links remain routed through pH7Builder. *}
{{ $terms_url = Framework\Mvc\Router\Uri::get('page', 'main', 'terms') }}
{{ $privacy_url = Framework\Mvc\Router\Uri::get('page', 'main', 'privacy') }}

<div id="disclaimer-dialog">
    <div class="center">
        <h1>Bienvenido a DeseoCerca</h1>

        <p class="dc-adult-note">
            DeseoCerca es una plataforma social y de descubrimiento de perfiles exclusiva para personas adultas.
            No se permite el acceso de menores de 18 años, la explotación sexual, la trata de personas,
            el contenido íntimo no consentido ni la oferta o intermediación de servicios sexuales de pago.
        </p>

        <p class="bold">
            Para continuar, confirma que tienes <span class="underline">18 años o más</span>.
        </p>

        <p>
            <button id="agree-over18" class="btn btn-success btn-lg">Tengo 18 años o más</button>
            <button id="disagree-under18" class="btn btn-secondary btn-lg">Soy menor de 18 años</button>
        </p>

        <p>
            <small>
                {lang 'Al entrar en DeseoCerca aceptas los <a href="%0%" target="_blank" rel="nofollow noopener">Términos de Uso</a> y la <a href="%1%" target="_blank" rel="nofollow noopener">Política de Privacidad</a>.', $terms_url, $privacy_url}
            </small>
        </p>
    </div>
</div>
<div id="disclaimer-background"></div>
