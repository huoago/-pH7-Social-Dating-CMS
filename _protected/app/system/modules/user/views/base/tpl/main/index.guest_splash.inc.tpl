{if $is_bg_video}
    {manual_include 'splash_video_background.inc.tpl'}
{/if}

<section class="dc-splash">
    <div class="dc-splash-topbar">
        <div class="dc-brand-lockup">
            <strong>DeseoCerca</strong>
            <span>Solo adultos 18+</span>
        </div>
        <a href="{{ $design->url('user','main','login') }}" class="btn btn-default dc-login-link">
            Iniciar sesión
        </a>
    </div>

    <div class="dc-splash-grid">
        <div class="dc-splash-hero animated fadeInLeft">
            <div class="dc-eyebrow">DESCUBRE · CONECTA · DECIDE TÚ</div>
            <h1>Personas cerca de ti, sin complicaciones.</h1>
            <p class="dc-hero-copy">
                Explora perfiles de adultos en Perú, encuentra personas por ubicación y empieza una conversación privada cuando quieras.
            </p>

            <div class="dc-trust-row" aria-label="Funciones de seguridad">
                <span>18+ obligatorio</span>
                <span>Perfiles moderados</span>
                <span>Bloqueo y denuncia</span>
                <span>Privacidad primero</span>
            </div>

            {manual_include 'user_promo_block.inc.tpl'}
        </div>

        <aside class="dc-signup-card animated fadeInRight">
            <div class="dc-signup-heading">
                <span class="dc-step-label">CREA TU PERFIL</span>
                <h2>Empieza gratis</h2>
                <p>Regístrate para descubrir personas y perfiles cerca de ti.</p>
            </div>
            {{ JoinForm::step1() }}
            <p class="dc-signup-note">
                Al registrarte confirmas que tienes 18 años o más y aceptas las normas de la comunidad.
            </p>
        </aside>
    </div>

    <div class="dc-existing-login animated fadeInDown">
        {{ LoginSplashForm::display() }}
    </div>
</section>
