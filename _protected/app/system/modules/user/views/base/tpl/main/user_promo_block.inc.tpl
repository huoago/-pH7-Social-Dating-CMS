<div class="dc-discovery-preview">
    <div class="dc-section-heading">
        <div>
            <span class="dc-step-label">CERCA DE TI</span>
            <h2>Descubre perfiles recientes</h2>
        </div>
        <span class="dc-location-chip">Perú · Lima primero</span>
    </div>

    {if $is_users_block}
        <div class="center profiles_window thumb pic_block dc-profile-window">
            {{ $userDesignModel->profiles(0, $number_profiles) }}
        </div>
    {/if}

    <div class="dc-promo-copy" id="promo_text">
        <p>
            Usa ubicación, edad y preferencias para encontrar perfiles relevantes. Tú decides con quién hablar y puedes bloquear o denunciar en cualquier momento.
        </p>
    </div>
</div>
