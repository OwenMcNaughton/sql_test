CREATE TABLE Factions
( 
    name                VARCHAR(100)    NOT NULL,
    leader              VARCHAR(100)    NOT NULL,
    description         VARCHAR(1000)   NOT NULL,
    population          BIGINT          DEFAULT 0 CHECK (population >= 0),

    PRIMARY KEY (name)
);

CREATE TABLE Areas
( 
    region              VARCHAR(100)    NOT NULL,
    sector              VARCHAR(100)    NOT NULL,
    population          BIGINT          DEFAULT 0 CHECK (population >= 0),

    PRIMARY KEY (region, sector)
);

CREATE TABLE Planets
(
    name                VARCHAR(100)    NOT NULL,
    moons               SMALLINT        NOT NULL,
    population          BIGINT          DEFAULT 0 CHECK (population >= 0),
    planet_type         VARCHAR(100)    NOT NULL,
    faction_name        VARCHAR(100)    NOT NULL,
    region              VARCHAR(100)    NOT NULL,
    sector              VARCHAR(100)    NOT NULL,
    
    PRIMARY KEY (name),
    FOREIGN KEY (faction_name) REFERENCES Factions(name)
        ON DELETE CASCADE,
    FOREIGN KEY (region, sector) REFERENCES Areas(region, sector)
        ON DELETE CASCADE,
    
    CONSTRAINT chk_planet_type CHECK (planet_type IN (
        "Desert", "Ice", "Terran", "Gas Giant", "Ecumenopolis", "Barren", "Oceanic", "Volcanic"))
);

CREATE TABLE Films
(
    episode_number      SMALLINT        NOT NULL,
    name                VARCHAR(100)    NOT NULL,
    year_released       INT             NOT NULL,
    
    PRIMARY KEY (episode_number),
    UNIQUE (name)
);

CREATE TABLE Species
(
    name                VARCHAR(100)    NOT NULL,
    homeworld           VARCHAR(100)    NOT NULL,
    
    PRIMARY KEY (name),
    FOREIGN KEY (homeworld) REFERENCES Planets (name)
        ON DELETE CASCADE
);

CREATE TABLE Demographics
(
    planet_name         VARCHAR(100)    NOT NULL,
    species_name        VARCHAR(100)    NOT NULL,
    percentage          FLOAT(32)       NOT NULL CHECK (percentage <= 1.0),
    
    PRIMARY KEY (planet_name, species_name),
    FOREIGN KEY (planet_name) REFERENCES Planets (name),
    FOREIGN KEY (species_name) REFERENCES Species (name)
);

CREATE TABLE Hyperlanes
(
    name                VARCHAR(100)    NOT NULL,
    year_founded        INT             NOT NULL,
    founders            VARCHAR(100)    NOT NULL,
    
    PRIMARY KEY (name),
    FOREIGN KEY (founders) REFERENCES Species (name)
        ON DELETE CASCADE
);

CREATE TABLE TradeRoutes
(
    hyperlane_name      VARCHAR(100)    NOT NULL,
    planet_name         VARCHAR(100)    NOT NULL,
    
    PRIMARY KEY (hyperlane_name, planet_name),
    FOREIGN KEY (hyperlane_name) REFERENCES Hyperlanes(name)
        ON DELETE CASCADE,
    FOREIGN KEY (planet_name) REFERENCES Planets(name)
        ON DELETE CASCADE
);

CREATE TABLE FilmAppearances
(
    film_number         SMALLINT        NOT NULL,
    planet_name         VARCHAR(100)    NOT NULL,
    
    PRIMARY KEY (film_number, planet_name),
    FOREIGN KEY (film_number) REFERENCES Films(episode_number)
        ON DELETE CASCADE,
    FOREIGN KEY (planet_name) REFERENCES Planets(name)
        ON DELETE CASCADE
);

DELIMITER $$
CREATE TRIGGER planet_chk_insert AFTER INSERT ON Planets
FOR EACH ROW
BEGIN
    IF NEW.planet_type NOT IN (
       "Desert", "Ice", "Terran", "Gas Giant", "Ecumenopolis", "Barren", "Oceanic", "Volcanic") THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Invalid planet_type";
    END IF;
        
    IF NEW.population < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Population must be non-negative";
    END IF;
    
    UPDATE Areas
    SET population = population + (New.population)
    WHERE region = New.region AND sector = New.sector;
    
    UPDATE Factions
    SET population = population + (New.population)
    WHERE name = New.faction_name;
END;
$$

DELIMITER $$
CREATE TRIGGER planet_chk_update AFTER UPDATE ON Planets
FOR EACH ROW
BEGIN
    IF NEW.planet_type NOT IN (
       "Desert", "Ice", "Terran", "Gas Giant", "Ecumenopolis", "Barren", "Oceanic", "Volcanic") THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Invalid planet_type";
    END IF;
    
    IF NEW.population < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Population must be non-negative";
    END IF;
    
    UPDATE Areas
    SET population = population + (New.population - Old.population)
    WHERE region = New.region AND sector = New.sector;
    
    UPDATE Factions
    SET population = population + (New.population - Old.population)
    WHERE name = New.faction_name;
END;
$$

DELIMITER $$
CREATE TRIGGER demographics_chk_insert AFTER INSERT ON Demographics
FOR EACH ROW
BEGIN
    DECLARE total_planet_percentage FLOAT(32);
    
    SET @total_planet_percentage :=
    (
        SELECT SUM(percentage)
        FROM Demographics
        WHERE planet_name = new.planet_name
    );
    
    IF @total_planet_percentage > 1.0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Total planet percentage must be <= 1.0";
    END IF;
END;
$$

DELIMITER $$
CREATE TRIGGER demographics_chk_update AFTER UPDATE ON Demographics
FOR EACH ROW
BEGIN
    DECLARE total_planet_percentage FLOAT(32);
    
    SET @total_planet_percentage :=
    (
        SELECT SUM(percentage)
        FROM Demographics
        WHERE planet_name = new.planet_name
    );
    
    IF @total_planet_percentage > 1.0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "Total planet percentage must be <= 1.0";
    END IF;
END;
$$

CREATE FUNCTION UnknownPopn (planet VARCHAR(100)) RETURNS FLOAT(32)
BEGIN
    DECLARE rowcount BIGINT;
    DECLARE total_percentage FLOAT(32);
    DECLARE total_popn FLOAT(32);

    SELECT population
    INTO @total_popn
    FROM Planets
    WHERE name = planet;

    SELECT SUM(percentage)
    INTO @total_percentage
    FROM Demographics
    WHERE planet_name = planet;
    
    SELECT COUNT(*)
    INTO @rowcount
    FROM Demographics
    WHERE planet_name = planet;
    
    IF @rowcount < 1 THEN
        RETURN @total_popn;
    END IF;
    
    RETURN ROUND(@total_popn - (@total_popn * @total_percentage));
END;

CREATE VIEW PlanetDemographics AS
SELECT p.name AS planet_name, 
       group_concat(concat(d.species_name, "(", ROUND(p.population*d.percentage), ")")
       ORDER BY d.percentage DESC) AS species_breakdown,
       UnknownPopn(p.name) AS unknown_species
FROM Planets AS p
LEFT OUTER JOIN Demographics AS d ON d.planet_name = p.name
GROUP BY p.name;

CREATE VIEW PlanetAppearanceCount AS
SELECT planet_name, COUNT(planet_name) AS appearance_count
FROM FilmAppearances
GROUP BY planet_name
ORDER BY appearance_count DESC;

CREATE VIEW HyperlanePopulation AS
SELECT tr.hyperlane_name, SUM(population) AS population
FROM Planets p 
JOIN TradeRoutes tr ON p.name = tr.planet_name
GROUP BY tr.hyperlane_name
ORDER BY population DESC;

CREATE FUNCTION Capital (faction VARCHAR(100)) RETURNS VARCHAR(100)
BEGIN
    DECLARE planet_name VARCHAR(100) DEFAULT "";
        SELECT name
        INTO planet_name
        FROM Planets 
        WHERE faction_name = faction 
        ORDER BY population DESC
        LIMIT 1;
    RETURN planet_name;
END;

CREATE VIEW FactionCapitals AS
SELECT f.name, Capital(f.name) as capital_planet
FROM Planets p
JOIN Factions f ON p.faction_name = f.name
GROUP BY f.name
ORDER BY f.population;

CREATE VIEW PlanetTypes AS
SELECT planet_type, Count(planet_type) AS amount, Sum(population) AS total_popn, 
       CAST(Sum(population)/Count(planet_type) AS UNSIGNED) AS average_popn
FROM Planets
GROUP BY planet_type
ORDER BY amount DESC;

INSERT INTO Films (episode_number, name, year_released) VALUES
    (1, "The Phantom Menace", 1999),
    (2, "The Clone Wars", 2002),
    (3, "Revenge of the Sith", 2005),
    (4, "A New Hope", 1977),
    (5, "The Empire Strike Back", 1980),
    (6, "Return of the Jedi", 1983);
    
INSERT INTO Factions (name, leader, description) VALUES 
    ("Galactic Empire", "Darth Sidious", "Dictatorship which replaced the Galactic Republic"),
    ("Rebel Alliance", "Mon Mothma", "Resistance formed to oppose the Galactic Empire"),
    ("Trade Federation", "Nute Gunray", "Interstellar shipping and trade conglomerate"),
    ("The Hutts", "Jabba", "Crime family/cartel"),
    ("The Mandalorians", "Mandalore", "Nomadic group of clan-based warriors");
    
INSERT INTO Areas (region, sector) VALUES
    ("Outer Rim", "Arkanis"),
    ("Outer Rim", "Rishi Maze"),
    ("Outer Rim", "IX"),
    ("Outer Rim", "XIII"),
    ("Outer Rim", "Hutt Space"),
    ("Core Worlds", "Corusca"),
    ("Core Worlds", "Kuat"),
    ("Inner Rim", "Quelli"),
    ("Mid Rim", "Chommel"),
    ("Mid Rim", "Seswenna"),
    ("Mid Rim", "Kastolar"),
    ("Colonies", "Kuat");
    
INSERT INTO Planets (name, moons, population, planet_type, faction_name, region, sector) VALUES
    ("Coruscant", 3, 821000000000, "Ecumenopolis", "Galactic Empire", "Core Worlds", "Corusca"),
    ("Tatooine", 3, 260000, "Desert", "The Hutts", "Outer Rim", "Arkanis"),
    ("Neimoidia", 1, 2570000000, "Barren", "Trade Federation", "Colonies", "Kuat"),
    ("Nal Hutta", 0, 22800000000, "Terran", "The Hutts", "Outer Rim", "Hutt Space"),
    ("Naboo", 2, 4520000000, "Terran", "Rebel Alliance", "Mid Rim", "Chommel"),
    ("Yavin", 4, 0, "Gas Giant", "Rebel Alliance", "Outer Rim", "Rishi Maze"),
    ("Mustafar", 0, 20000, "Volcanic", "Galactic Empire", "Outer Rim", "IX"),
    ("Kamino", 1, 1200000000, "Oceanic", "Galactic Empire", "Outer Rim", "Rishi Maze"),
    ("Sullust", 1, 185000000, "Barren", "Galactic Empire", "Mid Rim", "Seswenna"),
    ("Duro", 0, 1610000000, "Barren", "Galactic Empire", "Core Worlds", "Corusca"),
    ("Corellia", 3, 3100000000, "Terran", "Galactic Empire", "Core Worlds", "Corusca"),
    ("Dagobah", 1, 1, "Terran", "Rebel Alliance", "Outer Rim", "XIII"),
    ("Taris", 1, 145000000000, "Ecumenopolis", "Galactic Empire", "Inner Rim", "Quelli"),
    ("Geonosis", 15, 3750000000, "Desert", "The Hutts", "Outer Rim", "Arkanis"),
    ("Mandalore", 1, 75500000, "Barren", "The Mandalorians", "Inner Rim", "Quelli"),
    ("Forest Moon of Endor", 0, 35000000, "Terran", "Galactic Empire", "Outer Rim", "IX"),
    ("Bespin", 42, 5800000, "Gas Giant", "Galactic Empire", "Outer Rim", "IX"),
    ("Alderaan", 0, 6700000000, "Terran", "Rebel Alliance", "Core Worlds", "Kuat"),
    ("Hoth", 3, 10, "Ice", "Rebel Alliance", "Outer Rim", "IX"),
    ("Utapau", 9, 45200000, "Desert", "The Mandalorians", "Outer Rim", "XIII"),
    ("Kashyyyk", 3, 56900000, "Terran", "Rebel Alliance", "Mid Rim", "Kastolar");

INSERT INTO Species (name, homeworld) VALUES
    ("Human", "Coruscant"),
    ("Neimoidian", "Neimoidia"),
    ("Gungan", "Naboo"),
    ("Sullustan", "Sullust"),
    ("Hutt", "Nal Hutta"),
    ("Duros", "Duro"),
    ("Wookiee", "Kashyyyk"),
    ("Geonosian", "Geonosis"),
    ("Kaminoan", "Kamino"),
    ("Pau'an", "Utapau"),
    ("Utai", "Utapau"),
    ("Ewok", "Forest Moon of Endor"),
    ("Jawa", "Tatooine"),
    ("Taung", "Coruscant");
    
INSERT INTO Demographics (planet_name, species_name, percentage) VALUES
    ("Coruscant", "Human", 0.65),
    ("Coruscant", "Duros", 0.15),
    ("Coruscant", "Sullustan", 0.05),
    ("Coruscant", "Hutt", 0.002),
    ("Coruscant", "Taung", 0.04),
    ("Tatooine", "Jawa", 0.2),
    ("Tatooine", "Human", 0.6),
    ("Tatooine", "Hutt", 0.001),
    ("Tatooine", "Duros", 0.1),
    ("Neimoidia", "Human", 0.2),
    ("Neimoidia", "Neimoidian", 0.7),
    ("Nal Hutta", "Hutt", 0.7),
    ("Naboo", "Human", 0.3),
    ("Naboo", "Gungan", 0.6),
    ("Mustafar", "Human", 0.95),
    ("Kamino", "Kaminoan", 1.0),
    ("Sullust", "Sullustan", 0.8),
    ("Sullust", "Duros", 0.1),
    ("Duro", "Duros", 0.7),
    ("Duro", "Human", 0.2),
    ("Corellia", "Human", 0.9),
    ("Corellia", "Neimoidian", 0.02),
    ("Corellia", "Duros", 0.04),
    ("Taris", "Human", 0.7),
    ("Taris", "Duros", 0.15),
    ("Taris", "Neimoidian", 0.1),
    ("Taris", "Hutt", 0.005),
    ("Geonosis", "Geonosian", 0.99),
    ("Geonosis", "Hutt", 0.01),
    ("Mandalore", "Taung", 0.9),
    ("Mandalore", "Duros", 0.08),
    ("Forest Moon of Endor", "Ewok", 1.0),
    ("Bespin", "Human", 0.9),
    ("Bespin", "Sullustan", 0.07),
    ("Alderaan", "Human", 0.95),
    ("Utapau", "Utai", 0.7),
    ("Utapau", "Pau'an", 0.2),
    ("Utapau", "Duros", 0.06),
    ("Kashyyyk", "Wookiee", 0.9);
    
INSERT INTO Hyperlanes (name, year_founded, founders) VALUES
    ("Rimma Trade Route", -5500, "Sullustan"),
    ("Perlemian Trade Route", -25000, "Human"),
    ("Hydian Way", -3700, "Duros"),
    ("Corellian Run", -24500, "Human"),
    ("Gordian Reach", -1000, "Neimoidian"),
    ("Corellian Trade Spine", -25000, "Human");
    
INSERT INTO TradeRoutes (hyperlane_name, planet_name) VALUES
    ("Rimma Trade Route", "Sullust"),
    ("Rimma Trade Route", "Dagobah"),
    ("Rimma Trade Route", "Utapau"),
    ("Perlemian Trade Route", "Coruscant"),
    ("Perlemian Trade Route", "Naboo"),
    ("Hydian Way", "Taris"),
    ("Hydian Way", "Neimoidia"),
    ("Hydian Way", "Sullust"),
    ("Corellian Run", "Coruscant"),
    ("Corellian Run", "Corellia"),
    ("Corellian Run", "Nal Hutta"),
    ("Corellian Run", "Tatooine"),
    ("Corellian Run", "Geonosis"),
    ("Corellian Trade Spine", "Corellia"),
    ("Corellian Trade Spine", "Duro"),
    ("Corellian Trade Spine", "Nal Hutta"),
    ("Gordian Reach", "Yavin"),
    ("Gordian Reach", "Kashyyyk"),
    ("Gordian Reach", "Nal Hutta");
    
INSERT INTO FilmAppearances (film_number, planet_name) VALUES
    (1, "Naboo"),
    (1, "Tatooine"),
    (1, "Coruscant"),
    (2, "Coruscant"),
    (2, "Tatooine"),
    (2, "Kamino"),
    (2, "Naboo"),
    (2, "Geonosis"),
    (3, "Coruscant"),
    (3, "Mustafar"),
    (3, "Alderaan"),
    (3, "Dagobah"),
    (3, "Tatooine"),
    (3, "Utapau"),
    (3, "Kashyyyk"),
    (4, "Tatooine"),
    (4, "Yavin"),
    (4, "Alderaan"),
    (5, "Dagobah"),
    (5, "Hoth"),
    (5, "Bespin"),
    (6, "Forest Moon of Endor"),
    (6, "Tatooine"),
    (6, "Dagobah");