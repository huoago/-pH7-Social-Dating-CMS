<section class="dc-moderation-dashboard">
    <header>
        <span class="dc-eyebrow">DeseoCerca · Trust & Safety</span>
        <h1>Centro de moderación</h1>
        <p>Revisa primero identidad visual, contenido multimedia y denuncias. Durante V1, avatar, fotos y videos quedan sujetos a aprobación manual.</p>
    </header>

    <div class="dc-moderation-grid">
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'moderator','avatar') }}">
            <strong>Fotos de perfil</strong>
            <span>Aprobar o rechazar avatares pendientes.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'moderator','picture') }}">
            <strong>Fotografías</strong>
            <span>Revisar imágenes cargadas por usuarios.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'moderator','picturealbum') }}">
            <strong>Álbumes</strong>
            <span>Revisar álbumes antes de exposición pública.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'moderator','video') }}">
            <strong>Videos</strong>
            <span>Control manual del contenido de video.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url('report','admin','index') }}">
            <strong>Denuncias</strong>
            <span>Investigar reportes enviados por la comunidad.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'user','browse') }}">
            <strong>Usuarios</strong>
            <span>Buscar, revisar, suspender o gestionar cuentas.</span>
        </a>
        <a class="dc-moderation-card" href="{{ $design->url(PH7_ADMIN_MOD,'setting','moderation') }}">
            <strong>Reglas de moderación</strong>
            <span>Verificar que la aprobación manual permanezca activa.</span>
        </a>
    </div>

    <div class="dc-moderation-priority">
        <h2>Prioridad operativa V1</h2>
        <ol>
            <li>Menores o sospecha de edad: retirar de publicación y escalar inmediatamente.</li>
            <li>Explotación, trata, amenazas o contenido íntimo no consentido: retirar, preservar evidencia operativa necesaria y escalar.</li>
            <li>Suplantación, spam, acoso y datos personales expuestos: revisar cuenta, bloquear contenido y aplicar medidas.</li>
            <li>Contenido permitido pero pendiente: aprobar solo cuando cumpla las reglas y la identidad visual sea coherente con el perfil.</li>
        </ol>
    </div>
</section>
