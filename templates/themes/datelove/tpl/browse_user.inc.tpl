<section class="dc-discovery-page">
    <header class="dc-discovery-header">
        <div>
            <span class="dc-eyebrow">DeseoCerca · Perú</span>
            <h1>Descubre personas cerca de ti</h1>
            <p>Explora perfiles de adultos, filtra por ubicación y encuentra conexiones con más control y privacidad.</p>
        </div>
        <div class="dc-discovery-actions">
            <a class="btn btn-default" href="{{ $design->url('user','search','advanced') }}">Filtros avanzados</a>
            {if !$is_user_auth}
                <a class="btn btn-primary" href="{{ $design->url('user','signup','step1') }}">Crear perfil</a>
            {/if}
        </div>
    </header>

    <nav class="dc-location-shortcuts" aria-label="Zonas populares">
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Lima&avatar=1') }}">Lima</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Miraflores&avatar=1') }}">Miraflores</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=San%20Isidro&avatar=1') }}">San Isidro</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&city=Barranco&avatar=1') }}">Barranco</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&online=1&avatar=1') }}">En línea</a>
        <a href="{{ $design->url('user','browse','index','?country=PE&order=latest&avatar=1') }}">Nuevos</a>
    </nav>

    <div class="dc-discovery-layout">
        <aside class="dc-filter-panel" role="search">
            <div class="dc-filter-heading">
                <strong>Filtrar perfiles</strong>
                <span>18+</span>
            </div>
            {{ SearchUserCoreForm::quick(PH7_WIDTH_SEARCH_FORM) }}
        </aside>

        <main class="dc-results-panel">
            {if empty($users)}
                <div class="dc-empty-state">
                    <span class="dc-empty-icon" role="img" aria-label="Buscar">🔎</span>
                    <h2>No encontramos perfiles con esos filtros</h2>
                    <p>Prueba una zona más amplia, cambia el rango de edad o elimina algún filtro.</p>
                    <a class="btn btn-default" href="{{ $design->url('user','browse','index','?country=PE&city=Lima&avatar=1') }}">Ver Lima</a>
                </div>
            {else}
                <div class="dc-results-meta">
                    <strong>Perfiles disponibles</strong>
                    <span>Ordena por actividad, nuevos perfiles o personas en línea.</span>
                </div>

                <div class="dc-profile-grid">
                    {each $user in $users}
                        {{ $age = UserBirthDateCore::getAgeFromBirthDate($user->birthDate) }}
                        <article class="dc-profile-card">
                            <a class="dc-profile-photo" href="{% (new UserCore)->getProfileLink($user->username) %}" aria-label="Ver perfil de {% $str->extract($user->username, PH7_MAX_USERNAME_LENGTH_SHOWN) %}">
                                {{ $avatarDesign->get($user->username, $user->firstName, $user->sex, 400) }}
                                <span class="dc-status-dot">{{ UserDesignCoreModel::userStatus($user->profileId) }}</span>
                                {if $user->featured}
                                    <span class="dc-featured-badge">Destacado</span>
                                {/if}
                            </a>
                            <div class="dc-profile-card-body">
                                <div class="dc-profile-title-row">
                                    <a href="{% (new UserCore)->getProfileLink($user->username) %}">
                                        <strong>{% $str->extract($user->username, PH7_MAX_USERNAME_LENGTH_SHOWN) %}</strong>
                                    </a>
                                    <span>{age}</span>
                                </div>
                                <div class="dc-profile-location">
                                    <span>📍</span>
                                    <span>{% $str->upperFirst($user->city) %}{if !empty($user->state)}, {% $str->upperFirst($user->state) %}{/if}</span>
                                </div>
                                <div class="dc-profile-tags">
                                    <span>{lang $user->sex}</span>
                                    <span>{lang 'Looking for:'} {lang $user->matchSex}</span>
                                </div>
                            </div>

                            {if $is_admin_auth}
                                <div class="dc-admin-inline">
                                    <a href="{{ $design->url(PH7_ADMIN_MOD,'user','loginuseras',$user->profileId) }}">Entrar como usuario</a>
                                    {if $user->ban == UserCore::BAN_STATUS}
                                        {{ $design->popupLinkConfirm(t('UnBan'), PH7_ADMIN_MOD, 'user', 'unban', $user->profileId) }}
                                    {else}
                                        {{ $design->popupLinkConfirm(t('Ban'), PH7_ADMIN_MOD, 'user', 'ban', $user->profileId) }}
                                    {/if}
                                </div>
                            {/if}
                        </article>
                    {/each}
                </div>

                <div class="dc-pagination">
                    {main_include 'page_nav.inc.tpl'}
                </div>
            {/if}
        </main>
    </div>
</section>
