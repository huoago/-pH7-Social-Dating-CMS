<section class="dc-search-page">
    <header class="dc-search-header">
        <span class="dc-eyebrow">Búsqueda avanzada · Perú</span>
        <h1>Encuentra perfiles con más precisión</h1>
        <p>Combina edad, ubicación, estado de conexión, foto y otros criterios. DeseoCerca está limitado a personas adultas.</p>
    </header>

    <nav class="dc-location-shortcuts" aria-label="Búsquedas rápidas por ubicación">
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Lima&avatar=1') }}">Lima</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Miraflores&avatar=1') }}">Miraflores</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=San%20Isidro&avatar=1') }}">San Isidro</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Barranco&avatar=1') }}">Barranco</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&online=1&avatar=1') }}">Solo en línea</a>
    </nav>

    <div class="dc-advanced-search-card">
        {{ SearchUserCoreForm::advanced() }}
    </div>

    <p class="dc-search-privacy-note">
        La ubicación mostrada se utiliza para descubrimiento por ciudad o zona. La versión V1 no publica coordenadas GPS exactas del usuario.
    </p>
</section>
